#!/usr/bin/env bash
# Choose and install dotfile components.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_ALL=false

case "${1:-}" in
  --all) INSTALL_ALL=true; shift ;;
  -h|--help)
    echo 'Usage: ./install.sh [--all] [git hunk nvim tmux wezterm]'
    exit
    ;;
esac

components=("$@")
all_components=(git hunk nvim tmux wezterm)
descriptions=(
  'Git and its default editor'
  'Hunk terminal diff viewer'
  'Neovim and command-line dependencies'
  'tmux and ~/.tmux.conf'
  'WezTerm and ~/.wezterm.lua'
)

choose_components() {
  local cursor=0 key rest i mark
  local last_index=$((${#all_components[@]} - 1))
  local selected=()

  for i in "${!all_components[@]}"; do
    selected+=(1)
  done

  trap 'printf "\033[?25h"' EXIT INT TERM
  printf '\033[?25l'

  while true; do
    printf '\033[H\033[2JChoose configs to install\n\n'
    printf '  Use ↑/↓ to move, Space to toggle, Enter to install.\n\n'

    for i in "${!all_components[@]}"; do
      [ "${selected[$i]}" -eq 1 ] && mark=x || mark=' '
      if [ "$i" -eq "$cursor" ]; then
        printf '\033[7m> [%s] %-10s %s\033[0m\n' \
          "$mark" "${all_components[$i]}" "${descriptions[$i]}"
      else
        printf '  [%s] %-10s %s\n' \
          "$mark" "${all_components[$i]}" "${descriptions[$i]}"
      fi
    done

    IFS= read -r -s -n 1 key
    case "$key" in
      '') break ;;
      ' ') selected[$cursor]=$((1 - selected[cursor])) ;;
      j) [ "$cursor" -eq "$last_index" ] || cursor=$((cursor + 1)) ;;
      k) [ "$cursor" -eq 0 ] || cursor=$((cursor - 1)) ;;
      $'\033')
        IFS= read -r -s -n 2 -t 1 rest || true
        case "$rest" in
          '[A') [ "$cursor" -eq 0 ] || cursor=$((cursor - 1)) ;;
          '[B') [ "$cursor" -eq "$last_index" ] || cursor=$((cursor + 1)) ;;
        esac
        ;;
    esac
  done

  components=()
  for i in "${!all_components[@]}"; do
    [ "${selected[$i]}" -eq 1 ] && components+=("${all_components[$i]}")
  done

  printf '\033[?25h\033[H\033[2J'
  trap - EXIT INT TERM
}

if [ "${#components[@]}" -eq 0 ]; then
  if ! $INSTALL_ALL && [ -t 0 ] && [ -t 1 ]; then
    choose_components
  else
    components=("${all_components[@]}")
  fi
fi

[ "${#components[@]}" -gt 0 ] || { echo 'Nothing selected.'; exit; }

for component in "${components[@]}"; do
  case "$component" in
    git|hunk|nvim|tmux|wezterm) ;;
    *) echo "Unknown component: $component" >&2; exit 2 ;;
  esac

  echo
  echo "Installing $component"
  "$ROOT/$component/install.sh"
done
