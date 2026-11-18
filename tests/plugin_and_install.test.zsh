#!/usr/bin/env zsh
# Hermetic tests for zsh-rl.plugin.zsh, fpath autoload, install.sh, and uninstall.sh.
# SPDX-License-Identifier: MIT

emulate -L zsh
setopt errexit nounset pipefail

unset FPATH ZSH ZSH_CUSTOM ZDOTDIR XDG_DATA_HOME

REPO_DIR=${0:A:h:h}

typeset -i pass=0 fail=0

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
trap 'rm -rf "$tmp"' EXIT

touch "$tmp/real"
ln -s real "$tmp/sym"

# 1. Plugin entrypoint (zsh-rl.plugin.zsh) + idempotent fpath
out=$(zsh -fc '
  autoload -Uz compinit && compinit -u -d "$1/zcompdump"
  source "$2/zsh-rl.plugin.zsh"
  source "$2/zsh-rl.plugin.zsh"
  typeset -i count=0
  for p in $fpath; do [[ $p == "$2/completions" ]] && (( ++count )); done
  print -r -- "count=$count comp=${_comps[rl]:-none}"
  rl "$1/sym"
' -- "$tmp" "$REPO_DIR")
expected="count=1 comp=_rl
$tmp/sym
$tmp/real"
assert_eq "plugin_entrypoint" "$out" "$expected"

# 2. Lazy $fpath autoload (`autoload -Uz rl`)
out=$(zsh -fc '
  fpath=("$2/functions" "$2/completions" $fpath)
  autoload -Uz rl
  rl "$1/sym"
  rl "$1/real"
' -- "$tmp" "$REPO_DIR")
expected="$tmp/sym
$tmp/real
$tmp/real"
assert_eq "fpath_autoload" "$out" "$expected"

# 3. Standalone single-file rl.zsh fallback (without completions/_rl on fpath)
cp "$REPO_DIR/rl.zsh" "$tmp/standalone_rl.zsh"
out=$(zsh -fc '
  autoload -Uz compinit && compinit -u -d "$1/zcompdump2"
  source "$1/standalone_rl.zsh"
  print -r -- "comp=${_comps[rl]:-none}"
  rl "$1/sym"
' -- "$tmp")
expected="comp=_files
$tmp/sym
$tmp/real"
assert_eq "standalone_fallback" "$out" "$expected"

# 4. install.sh & uninstall.sh in isolated HOME (OMZ custom, OMZ plugin, XDG site-functions, dry-run)
fake_home="$tmp/home_omz"
mkdir -p "$fake_home/.oh-my-zsh/custom"
touch "$fake_home/.zcompdump-stale"

# Dry run must not create links or delete zcompdump
HOME="$fake_home" "$REPO_DIR/install.sh" --dry-run >/dev/null
[[ ! -L "$fake_home/.oh-my-zsh/custom/rl.zsh" ]] && (( ++pass )) || { (( ++fail )); print -u2 "FAIL: dry-run created symlink"; }
[[ -f "$fake_home/.zcompdump-stale" ]] && (( ++pass )) || { (( ++fail )); print -u2 "FAIL: dry-run deleted zcompdump"; }

# Real OMZ custom install
HOME="$fake_home" "$REPO_DIR/install.sh" >/dev/null
p1="$fake_home/.oh-my-zsh/custom/rl.zsh"
p2="$fake_home/.oh-my-zsh/custom/completions/_rl"
assert_eq "omz_custom_rl_link" "${p1:A}" "$REPO_DIR/rl.zsh"
assert_eq "omz_custom_comp_link" "${p2:A}" "$REPO_DIR/completions/_rl"
[[ ! -e "$fake_home/.zcompdump-stale" ]] && (( ++pass )) || { (( ++fail )); print -u2 "FAIL: stale zcompdump remained"; }

# OMZ plugin install
HOME="$fake_home" "$REPO_DIR/install.sh" --omz-plugin >/dev/null
p3="$fake_home/.oh-my-zsh/custom/plugins/zsh-rl/zsh-rl.plugin.zsh"
assert_eq "omz_plugin_link" "${p3:A}" "$REPO_DIR/zsh-rl.plugin.zsh"

# Foreign symlink in site-functions must NOT be deleted by uninstall.sh
mkdir -p "$fake_home/.local/share/zsh/site-functions"
touch "$tmp/foreign_target"
ln -s "$tmp/foreign_target" "$fake_home/.local/share/zsh/site-functions/rl"

HOME="$fake_home" "$REPO_DIR/uninstall.sh" >/dev/null
[[ ! -e "$fake_home/.oh-my-zsh/custom/rl.zsh" ]] && (( ++pass )) || { (( ++fail )); print -u2 "FAIL: rl.zsh not removed"; }
[[ ! -e "$fake_home/.oh-my-zsh/custom/completions/_rl" ]] && (( ++pass )) || { (( ++fail )); print -u2 "FAIL: _rl not removed"; }
[[ ! -d "$fake_home/.oh-my-zsh/custom/plugins/zsh-rl" ]] && (( ++pass )) || { (( ++fail )); print -u2 "FAIL: plugin dir not removed"; }
[[ -L "$fake_home/.local/share/zsh/site-functions/rl" ]] && (( ++pass )) || { (( ++fail )); print -u2 "FAIL: foreign symlink removed"; }

# XDG site-functions fallback when Oh My Zsh is absent
fake_xdg="$tmp/home_xdg"
mkdir -p "$fake_xdg"
HOME="$fake_xdg" "$REPO_DIR/install.sh" >/dev/null
p4="$fake_xdg/.local/share/zsh/site-functions/rl"
p5="$fake_xdg/.local/share/zsh/site-functions/_rl"
assert_eq "xdg_fn_link" "${p4:A}" "$REPO_DIR/functions/rl"
assert_eq "xdg_comp_link" "${p5:A}" "$REPO_DIR/completions/_rl"
HOME="$fake_xdg" "$REPO_DIR/uninstall.sh" >/dev/null
[[ ! -e "$fake_xdg/.local/share/zsh/site-functions/rl" ]] && (( ++pass )) || { (( ++fail )); print -u2 "FAIL: xdg rl not removed"; }

print -r -- "plugin_and_install.test.zsh: pass=$pass fail=$fail"
(( fail == 0 ))
