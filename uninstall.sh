#!/usr/bin/env zsh
# Cleanly remove symlinks installed by ./install.sh.
# SPDX-License-Identifier: MIT

emulate -L zsh
set -euo pipefail

REPO_DIR="${0:A:h}"

remove_if_ours() {
  local target_path="$1"
  if [[ -L "$target_path" ]]; then
    local resolved="${target_path:A}"
    if [[ "$resolved" == "$REPO_DIR"/* ]]; then
      command rm -f "$target_path"
      print -r -- "==> Removed $target_path"
    fi
  fi
}

omz_custom="${ZSH_CUSTOM:-${ZSH:-$HOME/.oh-my-zsh}/custom}"
remove_if_ours "$omz_custom/rl.zsh"
remove_if_ours "$omz_custom/completions/_rl"
remove_if_ours "$omz_custom/plugins/zsh-rl/zsh-rl.plugin.zsh"
remove_if_ours "$omz_custom/plugins/zsh-rl/_rl"
if [[ -d "$omz_custom/plugins/zsh-rl" ]]; then
  command rmdir "$omz_custom/plugins/zsh-rl" 2>/dev/null || true
fi

site_dir="${XDG_DATA_HOME:-$HOME/.local/share}/zsh/site-functions"
remove_if_ours "$site_dir/rl"
remove_if_ours "$site_dir/_rl"

zdot="${ZDOTDIR:-$HOME}"
command rm -f "$zdot"/.zcompdump*(N)
print -r -- "==> Cleared Zsh completion dump in $zdot"
