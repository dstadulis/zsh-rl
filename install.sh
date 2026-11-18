#!/usr/bin/env zsh
# Symlink installer for zsh-rl (`rl` function and `_rl` completion).
# SPDX-License-Identifier: MIT

emulate -L zsh
set -euo pipefail

REPO_DIR="${0:A:h}"

usage() {
  cat <<'EOF'
Usage: ./install.sh [options]

Symlinks `rl` and its `_rl` Zsh completion from this repository into your
local Zsh configuration.

Options:
  --omz-custom      Link rl.zsh + completions/_rl into $ZSH_CUSTOM (default when Oh My Zsh is present)
  --omz-plugin      Link as an Oh My Zsh plugin under $ZSH_CUSTOM/plugins/zsh-rl
  --zsh-dir <dir>   Install functions/rl and completions/_rl into <dir> (default fallback: ~/.local/share/zsh/site-functions)
  --dry-run         Print actions without modifying the filesystem
  -h, --help        Show this help
EOF
}

mode=""
zsh_dir_override=""
dry_run=0

while (( $# > 0 )); do
  case "$1" in
    --omz-custom)
      mode="omz-custom"
      ;;
    --omz-plugin)
      mode="omz-plugin"
      ;;
    --zsh-dir)
      shift
      (( $# > 0 )) || { print -u2 "Error: --zsh-dir requires a directory argument"; exit 1; }
      zsh_dir_override="$1"
      mode="site-functions"
      ;;
    --dry-run)
      dry_run=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      print -u2 -r -- "Error: unknown option: $1"
      usage >&2
      exit 1
      ;;
  esac
  shift
done

omz_custom="${ZSH_CUSTOM:-${ZSH:-$HOME/.oh-my-zsh}/custom}"
if [[ -z "$mode" ]]; then
  if [[ -d "$omz_custom" || -d "${ZSH:-$HOME/.oh-my-zsh}" ]]; then
    mode="omz-custom"
  else
    mode="site-functions"
  fi
fi

run_link() {
  local src="$1" dst="$2"
  if (( dry_run )); then
    print -r -- "[dry-run] ln -sfn $src $dst"
    return 0
  fi
  command mkdir -p "${dst:h}"
  command chmod 755 "${dst:h}" 2>/dev/null || true
  command ln -sfn "$src" "$dst"
  print -r -- "==> Linked $dst -> $src"
}

refresh_zcompdump() {
  if (( dry_run )); then
    print -r -- "[dry-run] refresh ~/.zcompdump*"
    return 0
  fi
  local zdot="${ZDOTDIR:-$HOME}"
  command rm -f "$zdot"/.zcompdump*(N)
  print -r -- "==> Cleared stale Zsh completion dump in $zdot"
}

case "$mode" in
  omz-custom)
    run_link "$REPO_DIR/rl.zsh" "$omz_custom/rl.zsh"
    run_link "$REPO_DIR/completions/_rl" "$omz_custom/completions/_rl"
    refresh_zcompdump
    ;;
  omz-plugin)
    run_link "$REPO_DIR/zsh-rl.plugin.zsh" "$omz_custom/plugins/zsh-rl/zsh-rl.plugin.zsh"
    run_link "$REPO_DIR/completions/_rl" "$omz_custom/plugins/zsh-rl/_rl"
    refresh_zcompdump
    print -r -- "==> Ensure 'zsh-rl' is listed in plugins=(...) in ~/.zshrc"
    ;;
  site-functions)
    target_dir="${zsh_dir_override:-${XDG_DATA_HOME:-$HOME/.local/share}/zsh/site-functions}"
    run_link "$REPO_DIR/functions/rl" "$target_dir/rl"
    run_link "$REPO_DIR/completions/_rl" "$target_dir/_rl"
    refresh_zcompdump
    print -r -- "==> Ensure '$target_dir' is in \$fpath and run 'autoload -Uz rl' in ~/.zshrc"
    ;;
esac

print -r -- "==> Done! Open a new terminal or reload your shell (e.g. 'source ~/.zshrc' or 'exec zsh')."
