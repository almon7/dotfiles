#!/usr/bin/env bash
# Choose and install dotfile components.
# Exit on command failures, unset variables, and failed commands inside pipelines.
set -euo pipefail

# Resolve paths relative to this script so it works from any current directory.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_ALL=false

# --all bypasses the interactive picker; named components are accepted below.
case "${1:-}" in
  --all) INSTALL_ALL=true; shift ;;
  -h|--help)
    echo 'Usage: ./install.sh [--all] [agents codex git hunk nvim tmux wezterm]'
    exit
    ;;
esac

components=("$@")
all_components=(agents codex git hunk nvim tmux wezterm)
descriptions=(
  'Shared agent instructions'
  'Codex user skills'
  'Git and its default editor'
  'Hunk terminal diff viewer'
  'Neovim and command-line dependencies'
  'tmux and ~/.tmux.conf'
  'WezTerm and ~/.wezterm.lua'
)

# Show a keyboard-driven checklist and save the selected component names.
choose_components() {
  local cursor=0 key rest i mark
  local last_index=$((${#all_components[@]} - 1))
  local selected=()

  # Start with every component selected; Space toggles these 1/0 values.
  for i in "${!all_components[@]}"; do
    selected+=(1)
  done

  # Hide the cursor while drawing, but always restore it if the script is interrupted.
  trap 'printf "\033[?25h"' EXIT INT TERM
  printf '\033[?25l'

  # Redraw the complete menu after every key press using ANSI terminal codes.
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

    # Read one key without echoing it. Escape sequences are handled separately below.
    IFS= read -r -s -n 1 key
    case "$key" in
      '') break ;;
      ' ') selected[$cursor]=$((1 - selected[cursor])) ;;
      j) [ "$cursor" -eq "$last_index" ] || cursor=$((cursor + 1)) ;;
      k) [ "$cursor" -eq 0 ] || cursor=$((cursor - 1)) ;;
      $'\033')
        # Arrow keys arrive as Escape followed by a two-character suffix.
        IFS= read -r -s -n 2 -t 1 rest || true
        case "$rest" in
          '[A') [ "$cursor" -eq 0 ] || cursor=$((cursor - 1)) ;;
          '[B') [ "$cursor" -eq "$last_index" ] || cursor=$((cursor + 1)) ;;
        esac
        ;;
    esac
  done

  # Convert the numeric selection flags back into component names.
  components=()
  for i in "${!all_components[@]}"; do
    [ "${selected[$i]}" -eq 1 ] && components+=("${all_components[$i]}")
  done

  printf '\033[?25h\033[H\033[2J'
  trap - EXIT INT TERM
}

# With no names, use the picker on a terminal and install everything in automation.
if [ "${#components[@]}" -eq 0 ]; then
  if ! $INSTALL_ALL && [ -t 0 ] && [ -t 1 ]; then
    choose_components
  else
    components=("${all_components[@]}")
  fi
fi

[ "${#components[@]}" -gt 0 ] || { echo 'Nothing selected.'; exit; }

# Validate every name before using it as part of an executable path.
for component in "${components[@]}"; do
  case "$component" in
    agents|codex|git|hunk|nvim|tmux|wezterm) ;;
    *) echo "Unknown component: $component" >&2; exit 2 ;;
  esac

  echo
  echo "Installing $component"
  "$ROOT/$component/install.sh"
done

echo
echo 'Installation complete.'
