#!/usr/bin/env zsh
# Hermetic unit & POSIX VFS conformance suite for `rl`.
# SPDX-License-Identifier: MIT

emulate -L zsh
setopt errexit nounset pipefail

export LC_ALL=C

REPO_DIR=${0:A:h:h}
source "$REPO_DIR/rl.zsh"

typeset -i pass=0 fail=0 maxlinks=40
[[ $OSTYPE == (darwin|freebsd|openbsd|netbsd)* ]] && maxlinks=32

assert_eq() {
  local name=$1 actual=$2 expected=$3
  if [[ $actual == $expected ]]; then
    (( ++pass ))
  else
    (( ++fail ))
    print -u2 -r -- "FAIL [$name]: expected <$expected>, got <$actual>"
  fi
}

tmp=$(mktemp -d)
tmp=${tmp:P}
trap 'chmod -R u+rwx "$tmp" 2>/dev/null || true; rm -rf "$tmp"' EXIT

# 1. Plain regular file, FIFO, mode 000 file, and directory (0 symlinks)
touch "$tmp/plain_file" "$tmp/mode000"
chmod 000 "$tmp/mode000"
mkdir "$tmp/plain_dir"
mkfifo "$tmp/fifo"
assert_eq "plain_file" "$(rl "$tmp/plain_file")" "$tmp/plain_file"
assert_eq "mode000_file" "$(rl "$tmp/mode000")" "$tmp/mode000"
assert_eq "fifo_node" "$(rl "$tmp/fifo")" "$tmp/fifo"
assert_eq "plain_dir" "$(rl "$tmp/plain_dir")" "$tmp/plain_dir"
assert_eq "plain_dir_slash" "$(rl "$tmp/plain_dir/")" "$tmp/plain_dir"

# 2. Root /, ///, /., /..
assert_eq "root" "$(rl /)" "/"
assert_eq "root_slashes" "$(rl ///)" "/"
assert_eq "root_dot" "$(rl /.)" "/"
assert_eq "root_dotdot" "$(rl /..)" "/"

# 3. Multi-hop relative + .. symlinks
mkdir -p "$tmp/sub" "$tmp/dest"
touch "$tmp/dest/target"
ln -s "../dest/target" "$tmp/sub/hop2"
ln -s "sub/hop2" "$tmp/hop1"
out=$(rl "$tmp/hop1")
expected="$tmp/hop1
$tmp/sub/hop2
$tmp/dest/target"
assert_eq "multihop_rel" "$out" "$expected"
if (( $+commands[realpath] )); then
  assert_eq "multihop_realpath" "${out##*$'\n'}" "$(realpath "$tmp/hop1")"
fi

# 4. Intermediate directory symlink + .. inside target (kernel namei semantics)
mkdir -p "$tmp/real_parent/real_dir" "$tmp/fake_parent"
touch "$tmp/real_parent/real_sibling" "$tmp/fake_parent/real_sibling"
ln -s "$tmp/real_parent/real_dir" "$tmp/fake_parent/dir_sym"
ln -s "../real_sibling" "$tmp/real_parent/real_dir/up_link"
out=$(rl "$tmp/fake_parent/dir_sym/up_link")
expected="$tmp/fake_parent/dir_sym/up_link
$tmp/real_parent/real_dir/up_link
$tmp/real_parent/real_sibling"
assert_eq "dir_sym_dotdot_namei" "$out" "$expected"
if (( $+commands[realpath] )); then
  assert_eq "dir_sym_realpath" "${out##*$'\n'}" "$(realpath "$tmp/fake_parent/dir_sym/up_link")"
fi

# 5. Traversing the SAME directory symlink TWICE with distinct suffixes (valid, non-loop)
ln -s "$tmp/fake_parent/dir_sym/real_leaf" "$tmp/real_parent/real_dir/bounce"
touch "$tmp/real_parent/real_dir/real_leaf"
out=$(rl "$tmp/fake_parent/dir_sym/bounce")
expected="$tmp/fake_parent/dir_sym/bounce
$tmp/real_parent/real_dir/bounce
$tmp/fake_parent/dir_sym/real_leaf
$tmp/real_parent/real_dir/real_leaf"
assert_eq "same_dir_sym_twice" "$out" "$expected"

# 6. Symlinks targeting ., .., and /
ln -s . "$tmp/dot_sym"
ln -s .. "$tmp/sub/up_sym"
ln -s / "$tmp/root_sym"
assert_eq "dot_sym" "$(rl "$tmp/dot_sym")" "$tmp/dot_sym"$'\n'"$tmp"
assert_eq "up_sym" "$(rl "$tmp/sub/up_sym")" "$tmp/sub/up_sym"$'\n'"$tmp"
assert_eq "root_sym" "$(rl "$tmp/root_sym")" "$tmp/root_sym"$'\n'"/"

# 7. Direct self-loop (self -> self)
ln -s self "$tmp/self"
set +e
out=$(rl "$tmp/self" 2>"$tmp/err")
rc=$?
set -e
assert_eq "self_loop_rc" "$rc" "1"
assert_eq "self_loop_out" "$out" "$tmp/self"$'\n'"$tmp/self"
assert_eq "self_loop_err" "$(<"$tmp/err")" "rl: $tmp/self: Too many levels of symbolic links"

# 8. Mutual 2-cycle (cyc_a -> cyc_b -> cyc_a) and 3-cycle
ln -s cyc_b "$tmp/cyc_a"
ln -s cyc_a "$tmp/cyc_b"
set +e
out=$(rl "$tmp/cyc_a" 2>"$tmp/err")
rc=$?
set -e
assert_eq "cycle2_rc" "$rc" "1"
assert_eq "cycle2_out" "$out" "$tmp/cyc_a"$'\n'"$tmp/cyc_b"$'\n'"$tmp/cyc_a"
assert_eq "cycle2_err" "$(<"$tmp/err")" "rl: $tmp/cyc_a: Too many levels of symbolic links"

ln -s c2 "$tmp/c1"
ln -s c3 "$tmp/c2"
ln -s c1 "$tmp/c3"
set +e
out=$(rl "$tmp/c1" 2>"$tmp/err")
rc=$?
set -e
assert_eq "cycle3_rc" "$rc" "1"
assert_eq "cycle3_out" "$out" "$tmp/c1"$'\n'"$tmp/c2"$'\n'"$tmp/c3"$'\n'"$tmp/c1"

# 9. Growing non-repeating symlink bomb (grow -> grow/sub)
ln -s "grow/sub" "$tmp/grow"
set +e
out=$(rl "$tmp/grow" 2>"$tmp/err")
rc=$?
set -e
assert_eq "grow_bomb_rc" "$rc" "1"
assert_eq "grow_bomb_err" "$(<"$tmp/err")" "rl: $tmp/grow: Too many levels of symbolic links"
typeset -a grow_lines=("${(@f)out}")
assert_eq "grow_bomb_line_count" "${#grow_lines}" "$(( maxlinks + 1 ))"

# 10. Exact OS MAXSYMLINKS boundary (maxlinks OK, maxlinks+1 ELOOP)
mkdir "$tmp/chain"
touch "$tmp/chain/0"
for (( i = 1; i <= maxlinks + 1; i++ )); do
  ln -s "$(( i - 1 ))" "$tmp/chain/$i"
done
out=$(rl "$tmp/chain/$maxlinks")
assert_eq "chain_max_ok" "${out##*$'\n'}" "$tmp/chain/0"

over=$(( maxlinks + 1 ))
set +e
out=$(rl "$tmp/chain/$over" 2>"$tmp/err")
rc=$?
set -e
assert_eq "chain_over_rc" "$rc" "1"
assert_eq "chain_over_last" "${out##*$'\n'}" "$tmp/chain/1"
assert_eq "chain_over_err" "$(<"$tmp/err")" "rl: $tmp/chain/$over: Too many levels of symbolic links"

# 11. Dangling multi-hop symlink chain (d1 -> d2 -> missing)
ln -s d2 "$tmp/d1"
ln -s "$tmp/missing_target" "$tmp/d2"
set +e
out=$(rl "$tmp/d1" 2>"$tmp/err")
rc=$?
set -e
assert_eq "dangling_rc" "$rc" "1"
assert_eq "dangling_out" "$out" "$tmp/d1"$'\n'"$tmp/d2"$'\n'"$tmp/missing_target"
assert_eq "dangling_err" "$(<"$tmp/err")" "rl: $tmp/d1: No such file or directory"

# 12. Nonexistent input (stdout MUST stay empty)
set +e
out=$(rl "$tmp/totally_missing" 2>"$tmp/err")
rc=$?
set -e
assert_eq "missing_rc" "$rc" "1"
assert_eq "missing_empty_stdout" "$out" ""
assert_eq "missing_err" "$(<"$tmp/err")" "rl: $tmp/totally_missing: No such file or directory"

# 13. POSIX trailing slashes on file/dir symlinks
ln -s plain_file "$tmp/sym_to_file"
ln -s "plain_file/" "$tmp/sym_with_slash_to_file"
ln -s plain_dir "$tmp/sym_to_dir"
assert_eq "sym_to_dir_slash" "$(rl "$tmp/sym_to_dir/")" "$tmp/sym_to_dir"$'\n'"$tmp/plain_dir"

set +e
out=$(rl "$tmp/sym_to_file/" 2>"$tmp/err"); rc=$?
set -e
assert_eq "sym_to_file_slash_rc" "$rc" "1"
assert_eq "sym_to_file_slash_err" "$(<"$tmp/err")" "rl: $tmp/sym_to_file/: Not a directory"

set +e
out=$(rl "$tmp/sym_with_slash_to_file" 2>"$tmp/err"); rc=$?
set -e
assert_eq "sym_target_slash_file_rc" "$rc" "1"
assert_eq "sym_target_slash_file_err" "$(<"$tmp/err")" "rl: $tmp/sym_with_slash_to_file: Not a directory"

# 14. nonexistent/.. and plain_file/.. and sym_to_file/.. must NOT lexically collapse
for bad in "$tmp/no_such_dir/.." "$tmp/plain_file/.." "$tmp/sym_to_file/.."; do
  set +e
  out=$(rl "$bad" 2>"$tmp/err"); rc=$?
  set -e
  assert_eq "dotdot_guard_${bad}" "$rc" "1"
done

# 15. Pathological filenames: spaces, -dash, *glob*, [brackets], quotes, $dollar, newline
weird_dir="$tmp/dir [with] *spaces* & 'quotes' \"\$x\""
mkdir -p "$weird_dir"
touch "$weird_dir/real_end"
ln -s "$weird_dir/real_end" "$weird_dir/-weird-link"
(
  cd "$weird_dir"
  out=$(rl -- -weird-link)
  assert_eq "weird_dash_link" "$out" "$weird_dir/-weird-link"$'\n'"$weird_dir/real_end"
)

nl_dir="$tmp/nl_test"
mkdir -p "$nl_dir"
nl_target=$'line1\nline2'
touch "$nl_dir/$nl_target"
ln -s "$nl_target" "$nl_dir/nl_sym"
out=$(rl "$nl_dir/nl_sym")
assert_eq "newline_in_filename" "$out" "$nl_dir/nl_sym"$'\n'"$nl_dir/$nl_target"

# 16. Relative path inside symlinked $PWD + repointed $PWD
(
  cd "$tmp/fake_parent/dir_sym"
  assert_eq "cwd_symlink_dot" "$(rl .)" "$tmp/fake_parent/dir_sym"$'\n'"$tmp/real_parent/real_dir"
  out=$(rl ../real_sibling)
  assert_eq "cwd_symlink_dotdot" "${out##*$'\n'}" "$tmp/real_parent/real_sibling"
)

mkdir "$tmp/repoint1" "$tmp/repoint2"
touch "$tmp/repoint1/inside"
ln -s "$tmp/repoint1" "$tmp/repoint_sym"
(
  cd "$tmp/repoint_sym"
  rm "$tmp/repoint_sym"
  ln -s "$tmp/repoint2" "$tmp/repoint_sym"
  assert_eq "repointed_cwd" "$(rl inside)" "$tmp/repoint1/inside"
)

# 17. Permission denied (EACCES) — only when not running as root
if (( EUID != 0 )); then
  mkdir "$tmp/locked"
  touch "$tmp/locked/secret"
  chmod 000 "$tmp/locked"
  set +e
  out=$(rl "$tmp/locked/secret" 2>"$tmp/err"); rc=$?
  set -e
  chmod 700 "$tmp/locked"
  assert_eq "eacces_rc" "$rc" "1"
  assert_eq "eacces_stdout" "$out" ""
  assert_eq "eacces_err" "$(<"$tmp/err")" "rl: $tmp/locked/secret: Permission denied"
fi

# 18. Zero-fork proof: runs completely in-process with PATH=""
out=$(PATH="" rl "$tmp/hop1")
assert_eq "zero_fork_empty_path" "$out" "$tmp/hop1"$'\n'"$tmp/sub/hop2"$'\n'"$tmp/dest/target"

# 19. Piped stdin, empty argument, and --help
out=$(printf '%s\n' "$tmp/dot_sym" "$tmp/root_sym" | rl)
assert_eq "piped_stdin" "$out" "$tmp/dot_sym"$'\n'"$tmp"$'\n'"$tmp/root_sym"$'\n'"/"

set +e
out=$(rl "" 2>"$tmp/err"); rc=$?
set -e
assert_eq "empty_arg_rc" "$rc" "1"
assert_eq "empty_arg_err" "$(<"$tmp/err")" "rl: '': No such file or directory"

assert_eq "help_flag" "$(rl --help)" "usage: rl [--] <path> [...]"

# 20. Live OS symlinks cross-checked against realpath (when available)
if (( $+commands[realpath] )); then
  for sys_path in /etc/localtime /var /tmp /etc /bin/sh; do
    [[ -e $sys_path ]] || continue
    out=$(rl "$sys_path")
    assert_eq "sys_${sys_path}" "${out##*$'\n'}" "$(realpath "$sys_path")"
  done
fi

print -r -- "rl.test.zsh: pass=$pass fail=$fail"
(( fail == 0 ))
