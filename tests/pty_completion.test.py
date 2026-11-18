#!/usr/bin/env python3
"""Hermetic PTY suite verifying TTY multi-arg formatting and Zsh TAB completion."""
# SPDX-License-Identifier: MIT

import os
import pty
import select
import shutil
import sys
import tempfile
import time
from pathlib import Path

REPO_DIR = Path(__file__).resolve().parent.parent


def read_all(fd: int, timeout: float = 5.0) -> str:
    deadline = time.monotonic() + timeout
    chunks: list[bytes] = []
    while time.monotonic() < deadline:
        r, _, _ = select.select([fd], [], [], 0.1)
        if not r:
            continue
        try:
            data = os.read(fd, 4096)
        except OSError:
            break
        if not data:
            break
        chunks.append(data)
    return b"".join(chunks).decode("utf-8", "replace")


def read_until(fd: int, needle: str, timeout: float = 5.0) -> str:
    deadline = time.monotonic() + timeout
    buf = ""
    while time.monotonic() < deadline:
        if needle in buf:
            return buf
        r, _, _ = select.select([fd], [], [], 0.1)
        if not r:
            continue
        try:
            data = os.read(fd, 4096)
        except OSError:
            break
        if not data:
            break
        buf += data.decode("utf-8", "replace")
    raise AssertionError(f"Timed out waiting for {needle!r}; buffer={buf!r}")


def test_tty_multi_arg_formatting(tmp: Path) -> None:
    real_a = tmp / "real_a"
    real_b = tmp / "real_b"
    real_a.write_text("", encoding="utf-8")
    real_b.write_text("", encoding="utf-8")
    sym_a = tmp / "sym_a"
    sym_b = tmp / "sym_b"
    sym_a.symlink_to("real_a")
    sym_b.symlink_to("real_b")
    missing = tmp / "missing_x"

    pid, fd = pty.fork()
    if pid == 0:
        os.environ.pop("FPATH", None)
        os.environ["LC_ALL"] = "C"
        os.execvp(
            "zsh",
            [
                "zsh",
                "-fc",
                f'source "{REPO_DIR}/rl.zsh"; rl "{missing}" "{sym_a}" "{sym_b}"',
            ],
        )
    out = read_all(fd).replace("\r\n", "\n")
    _, status = os.waitpid(pid, 0)
    assert os.WIFEXITED(status) and os.WEXITSTATUS(status) == 1, f"unexpected status: {status}"

    expected = (
        f"rl: {missing}: No such file or directory\n"
        f"{sym_a}\n"
        f"{real_a}\n"
        f"\n"
        f"{sym_b}\n"
        f"{real_b}\n"
    )
    assert out == expected, f"TTY output mismatch:\nexpected:\n{expected!r}\ngot:\n{out!r}"


def test_interactive_tab_completion(tmp: Path) -> None:
    comp_dir = tmp / "work"
    comp_dir.mkdir()
    (comp_dir / "dangling_unique_link").symlink_to("nowhere")

    pid, fd = pty.fork()
    if pid == 0:
        os.environ.pop("FPATH", None)
        os.environ["LC_ALL"] = "C"
        os.environ["TERM"] = "xterm-256color"
        os.environ["ZDOTDIR"] = str(tmp)
        zshrc = tmp / ".zshrc"
        zshrc.write_text(
            f"""
PS1='READY> '
autoload -Uz compinit && compinit -u -d "{tmp}/.zcompdump"
source "{REPO_DIR}/zsh-rl.plugin.zsh"
cd "{comp_dir}"
""",
            encoding="utf-8",
        )
        os.execvp("zsh", ["zsh", "-i"])

    try:
        read_until(fd, "READY> ")
        # Complete dangling symlink via TAB and execute rl --help check
        os.write(fd, b"rl dang\t")
        completed = read_until(fd, "dangling_unique_link")
        assert "dangling_unique_link" in completed

        # Cancel line (^C), then verify --he<TAB> completes --help
        os.write(fd, b"\x03")
        read_until(fd, "READY> ")
        os.write(fd, b"rl --he\t")
        flag_completed = read_until(fd, "--help")
        assert "--help" in flag_completed

        os.write(fd, b"\r")
        read_until(fd, "usage: rl [--] <path> [...]")
        os.write(fd, b"exit\r")
        read_all(fd, timeout=1.0)
    finally:
        try:
            os.close(fd)
        except OSError:
            pass
        os.waitpid(pid, 0)


def main() -> None:
    raw_tmp = Path(tempfile.mkdtemp())
    tmp = raw_tmp.resolve()
    try:
        test_tty_multi_arg_formatting(tmp)
        test_interactive_tab_completion(tmp)
        print("pty_completion.test.py: pass=2 fail=0")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
