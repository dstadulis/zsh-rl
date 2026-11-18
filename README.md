# zsh-rl

`rl` ("real link") is a pure, in-process Zsh function that traces every symbolic link hop along a path—both **intermediate directory symlinks** and **leaf symlinks**—using the OS kernel's VFS (`namei`) resolution semantics until no links remain.

Zero external processes, zero subshells (`PATH=""` safe), ~0.26 ms for a 6-hop chain, MIT licensed.

---

## Why Not `realpath` or a `while readlink` Loop?

| Tool | What It Misses |
| :--- | :--- |
| `realpath foo` / `${foo:P}` | Prints **only the final destination**, hiding every intermediate hop (and gives no hop trace when a link in the middle is dangling). |
| `while [[ -L $p ]]; do p=$(readlink "$p"); done` | Inspects **only the leaf component**, spawns `fork()`/`execve()` subshells per hop (stripping trailing `\n` bytes from valid POSIX filenames), and resolves `sym_dir/../sibling` against the wrong parent directory. |

Consider `/etc/localtime` on macOS. A naive leaf-only `readlink` loop stops after **1 hop** (`/var/db/timezone/zoneinfo/America/Los_Angeles`) because `Los_Angeles` is a regular file—completely missing four directory symlinks (`/etc`, `/var`, `zoneinfo`, and `/var` again).

`rl` walks the path the same way the kernel's VFS `namei` does:

```zsh
$ rl /etc/localtime
/etc/localtime
/private/etc/localtime
/var/db/timezone/zoneinfo/America/Los_Angeles
/private/var/db/timezone/zoneinfo/America/Los_Angeles
/var/db/timezone/tz/2026f.1.0/zoneinfo/America/Los_Angeles
/private/var/db/timezone/tz/2026f.1.0/zoneinfo/America/Los_Angeles
```

Combine with Zsh's native `=cmd` expansion to trace commands in `$PATH`:

```zsh
$ rl =python3
/opt/homebrew/bin/python3
/opt/homebrew/Cellar/python@3.15/3.15.2/bin/python3
/opt/homebrew/Cellar/python@3.15/3.15.2/Frameworks/Python.framework/Versions/3.15/bin/python3
/opt/homebrew/Cellar/python@3.15/3.15.2/Frameworks/Python.framework/Versions/3.15/bin/python3.15
```

---

## Architecture: VFS `namei` in ~100 Lines of Zsh

In Unix, custody of symbolic links is split cleanly across the VFS boundary:

1. **The Filesystem** (APFS, ext4, XFS, NFS) stores only the `S_IFLNK` inode mode and an uninterpreted target byte string (`vnop_readlink` on XNU/BSD, `inode_operations->get_link` on Linux). It has no idea where that string leads—because symlinks can cross mount points into other filesystems.
2. **The OS Kernel VFS** (`bsd/vfs/vfs_lookup.c`, `fs/namei.c`) walks path components left-to-right, splices `S_IFLNK` targets onto the front of the remaining unwalked components, enforces `MAXSYMLINKS` (`32` on macOS/\*BSD, `40` on Linux → `ELOOP`), and stops when every component resolves to a non-`S_IFLNK` inode.

`rl` mirrors `fs/namei.c`'s two-loop state machine directly:

- **Single `(cur, rest)` invariant:** `cur` is always an already-verified, symlink-free directory path starting at `/`; `rest` is the queue of unwalked components. Intermediate directory symlinks and leaf symlinks require **zero separate code paths**—both splice their target onto the front of `rest` (resetting `cur=/` if absolute) and fold leading `..` against the canonical `cur`.
- **100% in-process syscalls:** Uses `zsh/stat` (`zstat -L -A`) and `zsh/system` (`$ERRNO` + `syserror`) directly in C inside the `zsh` process—no `/usr/bin/readlink`, no `/usr/bin/dirname`, no subshells, and exact OS `strerror(errno)` diagnostics (`ENOENT`, `ENOTDIR`, `EACCES`, `ENAMETOOLONG`, `ELOOP`).
- **Dual `ELOOP` defense:** Detects exact `(cur, rest)` state cycles (`a → b → a`) immediately upon cycle closure *and* bounds non-repeating expanding bombs (`a → a/b → a/b/b…`) at the exact OS `MAXSYMLINKS` threshold—while still permitting valid paths that traverse the same directory symlink multiple times with distinct suffixes.
- **Composable Unix path stream:** Outputs clean, newline-delimited absolute paths on `stdout` (diagnostics on `stderr`, exit `0` when the target exists, `1` on dangling/looping/missing paths, `2` on missing TTY usage).

---

## Installation

### Local Clone + Symlink Installer

```sh
git clone https://github.com/dstadulis/zsh-rl.git
cd zsh-rl
./install.sh          # Auto-detects Oh My Zsh ($ZSH_CUSTOM) or ~/.local/share/zsh/site-functions
```

Reload your shell (`source ~/.zshrc` or `exec zsh`). Run `./uninstall.sh` at any time to remove installed symlinks cleanly.

### Zsh Plugin Managers

- **Antidote** (`~/.zsh_plugins.txt`):
  ```text
  dstadulis/zsh-rl
  ```
- **Zinit** (`~/.zshrc`):
  ```zsh
  zinit light dstadulis/zsh-rl
  ```
- **Sheldon** (`~/.config/sheldon/plugins.toml`):
  ```toml
  [plugins.zsh-rl]
  github = "dstadulis/zsh-rl"
  ```
- **Znap** (`~/.zshrc`):
  ```zsh
  znap source dstadulis/zsh-rl
  ```
- **Oh My Zsh** (custom plugin clone):
  ```zsh
  git clone https://github.com/dstadulis/zsh-rl.git "${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-rl"
  # Add `zsh-rl` to plugins=(...) in ~/.zshrc
  ```

### Standard `$fpath` Autoload (No Plugin Manager)

```zsh
fpath=(/path/to/zsh-rl/functions /path/to/zsh-rl/completions $fpath)
autoload -Uz rl
```

### Single-File Drop-In

[`rl.zsh`](rl.zsh) is completely self-contained and can be sourced directly from anywhere (`source /path/to/rl.zsh`).

---

## Usage & Pipeline Composition

```zsh
# Trace one or more paths (blank-line separated on a TTY, pure path stream when piped):
rl /etc/localtime /var /tmp

# Inspect permissions and ownership of every hop in a symlink chain:
rl /etc/localtime | xargs ls -ld

# Jump to or edit the final resolved target:
nvim "$(rl ~/.zshrc | tail -n 1)"

# Pipe path streams from stdin:
which -a python3 | rl

# Dangling chains print every hop up to the missing target on stdout,
# emit kernel ENOENT on stderr, and exit 1:
$ ln -s /nonexistent/target broken && rl broken
/tmp/broken
/private/tmp/broken
/nonexistent/target
rl: broken: No such file or directory   # (stderr, exit 1)

# Paths starting with `-`:
rl -- -weird-link
```

---

## Repository Layout

```text
zsh-rl/
├── rl.zsh                          # Canonical in-process implementation
├── completions/_rl                 # Zsh tab-completion (#compdef rl)
├── functions/rl                    # Standard $fpath lazy autoload entrypoint
├── zsh-rl.plugin.zsh               # Plugin manager entrypoint (OMZ, Antidote, Zinit, Sheldon, Znap)
├── install.sh                      # Symlink installer (--omz-custom, --omz-plugin, --zsh-dir, --dry-run)
├── uninstall.sh                    # Clean symlink uninstaller
├── tests/
│   ├── rl.test.zsh                 # 60 unit & POSIX VFS conformance assertions
│   ├── plugin_and_install.test.zsh # Plugin, autoload, and hermetic installer/uninstaller tests
│   └── pty_completion.test.py      # Live PTY multi-arg formatting & interactive TAB-completion tests
└── Makefile
```

---

## Verification

All 78 test assertions are hermetic (no network access, isolated `$HOME`/`$ZDOTDIR`):

```sh
make test
```

---

## License

Released under the [MIT License](LICENSE).
