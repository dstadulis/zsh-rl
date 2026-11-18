# rl — trace symbolic link resolution hop-by-hop to the real inode path.
# Mirrors the kernel VFS two-loop design (fs/namei.c): an outer symlink-splice
# loop and an inner component-walk loop, entirely in-process via zsh/stat.
#
# SPDX-License-Identifier: MIT

function rl() {
  emulate -L zsh
  zmodload -F zsh/stat b:zstat
  zmodload -F zsh/system b:syserror

  [[ ${1:-} == (-h|--help) ]] && { print 'usage: rl [--] <path> [...]'; return 0; }
  [[ ${1:-} == -- ]] && shift

  if (( ! $# )); then
    [[ -t 0 ]] && { print -u2 'usage: rl [--] <path> [...]'; return 2; }
    local line
    while IFS= read -r line || [[ -n $line ]]; do argv+=("$line"); done
    (( $# )) || return 0
  fi

  local -i ret=0 hops must_dir printed sep=0 maxlinks=40
  [[ $OSTYPE == (darwin|freebsd|openbsd|netbsd)* ]] && maxlinks=32
  local base arg target start cur comp cand state last err msg
  [[ $PWD -ef . ]] && base=$PWD || base=${${:-.}:P}
  local -a rest parts lnk
  local -A seen

  for arg in "$@"; do
    hops=0 printed=0 err=

    if [[ -z $arg ]]; then
      err=ENOENT
    else
      [[ $arg == /* ]] && target=$arg || target=${base%/}/$arg
      [[ $arg == (|*/)(.|..|) ]] && must_dir=1 || must_dir=0
      cur=/ rest=()

      while true; do
        [[ $target == /* ]] && cur=/
        parts=("${(@s:/:)target}")
        rest=("${(@)parts:#(|.)}" "${(@)rest}")
        while [[ ${rest[1]} == .. ]]; do cur=${cur:h}; shift rest; done
        (( $#rest )) && state=${cur%/}/${(j:/:)rest} || state=$cur

        if (( ! hops )); then
          start=$state last=$state seen=("$start" 1)
        else
          if (( ! printed )); then
            (( sep )) && [[ -t 1 ]] && print
            printed=1
            print -r -- "$start"
          fi
          print -r -- "$state"
          last=$state
          (( $+seen[$state] )) && { err=ELOOP; break; }
          seen[$state]=1
        fi

        target=
        while (( $#rest )); do
          comp=${rest[1]}; shift rest
          [[ $comp == .. ]] && { cur=${cur:h}; continue; }
          cand=${cur%/}/$comp
          ERRNO=0
          if [[ -L $cand ]]; then
            (( ++hops > maxlinks )) && { err=ELOOP; break 2; }
            zstat -L -A lnk +link -- "$cand" 2>/dev/null || { err=ENOENT; break 2; }
            target=${lnk[1]}
            [[ -z $target ]] && { err=ENOENT; break 2; }
            (( ! $#rest )) && [[ $target == (|*/)(.|..|) ]] && must_dir=1
            break
          elif (( ERRNO )); then
            err=$ERRNO; break 2
          elif (( $#rest )) && [[ ! -d $cand ]]; then
            err=ENOTDIR; break 2
          fi
          cur=$cand
        done
        [[ -n $target ]] || break
      done

      [[ -z $err ]] && (( must_dir )) && [[ ! -d $cur ]] && err=ENOTDIR
    fi

    if [[ -n $err ]]; then
      syserror -e msg $err
      print -u2 -r -- "rl: ${arg:-''}: $msg"
      ret=1
    else
      if (( ! printed )); then
        (( sep )) && [[ -t 1 ]] && print
        printed=1
        print -r -- "$cur"
      elif [[ $cur != $last ]]; then
        print -r -- "$cur"
      fi
    fi
    (( printed )) && sep=1
  done

  return $ret
}

if (( $+functions[compdef] )); then
  () {
    emulate -L zsh
    local -a c=($^fpath/_rl(N))
    if (( $+functions[_rl] || $#c )); then
      autoload -Uz _rl
      compdef _rl rl
    else
      compdef _files rl
    fi
  }
fi
