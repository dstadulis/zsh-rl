# Zsh plugin entrypoint (Oh My Zsh, Antidote, Zinit, Sheldon, Znap, Zgenom).
# SPDX-License-Identifier: MIT

() {
  local dir=${${(%):-%x}:A:h}
  (( ${fpath[(Ie)$dir/completions]} )) || fpath=("$dir/completions" $fpath)
  source "$dir/rl.zsh"
}
