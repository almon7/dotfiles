#!/usr/bin/env bash
# Choose and install dotfile components.
# Exit on command failures, unset variables, and failed commands inside pipelines.
set -euo pipefail    # abort on an error, an unset variable, or a failing pipeline stage

# Resolve paths relative to this script so it works from any current directory.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"    # absolute path of the repository root
INSTALL_ALL=false    # set by --all to skip the picker

# --all bypasses the interactive picker; named components are accepted below.
case "${1:-}" in    # inspect only the first argument
  --all) INSTALL_ALL=true; shift ;;    # drop it so "$@" holds component names alone
  -h|--help)
    echo 'Usage: ./install.sh [--all] [agents codex context7 git hunk nvim tmux wezterm]'
    exit
    ;;
esac

components=("$@")    # component names given on the command line, possibly none
all_components=(agents codex context7 git hunk nvim tmux wezterm)    # every installable component
descriptions=(    # one line per component above, in the same order
  'Shared agent instructions and skills'
  'Codex settings check (does not install Codex)'
  'Context7 CLI for the find-docs skill'
  'Git and its default editor'
  'Hunk terminal diff viewer'
  'Neovim and command-line dependencies'
  'tmux and ~/.tmux.conf'
  'WezTerm and ~/.wezterm.lua'
)

# Show a keyboard-driven checklist and save the selected component names.
choose_components() {
  local cursor=0 key rest i mark    # highlighted row, the key read, its suffix, a loop index, the checkbox glyph
  local last_index=$((${#all_components[@]} - 1))    # the cursor may not move past this row
  local selected=()    # one flag per component

  # Start with every component selected; Space toggles these 1/0 values.
  for i in "${!all_components[@]}"; do    # iterate over indices, not values
    selected+=(1)
  done

  # Hide the cursor while drawing, but always restore it if the script is interrupted.
  trap 'printf "\033[?25h"' EXIT INT TERM    # show the cursor again however the function ends
  printf '\033[?25l'    # hide it for the duration

  # Redraw the complete menu after every key press using ANSI terminal codes.
  while true; do
    printf '\033[H\033[2JChoose configs to install\n\n'    # home the cursor, clear the screen, print the title
    printf '  Use ↑/↓ to move, Space to toggle, Enter to install.\n\n'

    for i in "${!all_components[@]}"; do    # one row per component
      [ "${selected[$i]}" -eq 1 ] && mark=x || mark=' '    # a ticked box or an empty one
      if [ "$i" -eq "$cursor" ]; then    # the highlighted row
        printf '\033[7m> [%s] %-10s %s\033[0m\n' \
          "$mark" "${all_components[$i]}" "${descriptions[$i]}"    # \033[7m reverses the video
      else
        printf '  [%s] %-10s %s\n' \
          "$mark" "${all_components[$i]}" "${descriptions[$i]}"    # padded to align the descriptions
      fi
    done

    # Read one key without echoing it. Escape sequences are handled separately below.
    IFS= read -r -s -n 1 key    # -s silences the echo, -n 1 returns without waiting for Enter
    case "$key" in
      '') break ;;    # Enter reads as empty: accept the selection
      ' ') selected[$cursor]=$((1 - selected[cursor])) ;;    # flip 0 and 1
      j) [ "$cursor" -eq "$last_index" ] || cursor=$((cursor + 1)) ;;    # vi-style down, stopping at the end
      k) [ "$cursor" -eq 0 ] || cursor=$((cursor - 1)) ;;    # vi-style up, stopping at the top
      $'\033')
        # Arrow keys arrive as Escape followed by a two-character suffix.
        IFS= read -r -s -n 2 -t 1 rest || true    # a lone Escape times out after a second
        case "$rest" in
          '[A') [ "$cursor" -eq 0 ] || cursor=$((cursor - 1)) ;;    # up arrow
          '[B') [ "$cursor" -eq "$last_index" ] || cursor=$((cursor + 1)) ;;    # down arrow
        esac
        ;;
    esac
  done

  # Convert the numeric selection flags back into component names.
  components=()    # this is the caller's variable, deliberately not local
  for i in "${!all_components[@]}"; do
    [ "${selected[$i]}" -eq 1 ] && components+=("${all_components[$i]}")    # keep the ticked ones
  done

  printf '\033[?25h\033[H\033[2J'    # restore the cursor and clear the menu away
  trap - EXIT INT TERM    # the trap has done its job
}

# With no names, use the picker on a terminal and install everything in automation.
if [ "${#components[@]}" -eq 0 ]; then    # nothing was named on the command line
  if ! $INSTALL_ALL && [ -t 0 ] && [ -t 1 ]; then    # a real terminal can drive the picker
    choose_components
  else
    components=("${all_components[@]}")    # --all, or a pipe or CI job with nobody to ask
  fi
fi

[ "${#components[@]}" -gt 0 ] || { echo 'Nothing selected.'; exit; }    # the picker allows an empty selection

# Validate every name before using it as part of an executable path.
for component in "${components[@]}"; do
  case "$component" in
    agents|codex|context7|git|hunk|nvim|tmux|wezterm) ;;    # a known name: nothing to do
    *) echo "Unknown component: $component" >&2; exit 2 ;;    # refuse to build a path from it
  esac

  echo
  echo "Installing $component"
  "$ROOT/$component/install.sh"    # each component installs itself
done

echo
echo 'Installation complete.'
