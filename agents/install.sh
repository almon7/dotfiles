#!/usr/bin/env bash
# Give every coding agent the same personal instructions.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LABEL=agents
source "$DIR/../install-lib.sh"

FILE="$DIR/AGENTS.md"
TARGETS="$DIR/targets"

usage() {
  printf 'Usage: %s [path ...]\n' "$0"
  printf 'Extra paths are linked to AGENTS.md and remembered in agents/targets.\n'
}

# Accept a typed path the way a shell would, so ~/.cursor/AGENTS.md works
# whether the shell expanded it or it arrived from the targets file verbatim.
expand_path() {
  case "$1" in
    '~') printf '%s\n' "$HOME" ;;
    '~/'*) printf '%s\n' "$HOME/${1#'~/'}" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

# List the extra targets, ignoring the comments and blank lines that document
# the file.
read_targets() {
  [ -f "$TARGETS" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      ''|'#'*) continue ;;
    esac
    printf '%s\n' "$line"
  done < "$TARGETS"
}

# Record a path so later runs, and other machines, link it without asking again.
remember_target() {
  local path=$1 known

  while IFS= read -r known; do
    if [ "$(expand_path "$known")" = "$(expand_path "$path")" ]; then
      return 0
    fi
  done < <(read_targets)

  printf '%s\n' "$path" >> "$TARGETS"
  log "Added $path to agents/targets"
}

# Ask for the paths of any other tool that reads a standing instructions file.
prompt_for_targets() {
  local answer

  printf '[%s] Link the instructions anywhere else? Path (blank to finish): ' "$LABEL"
  while IFS= read -r answer; do
    if [ -n "$answer" ]; then
      remember_target "$answer"
    else
      break
    fi
    printf '[%s] Another path (blank to finish): ' "$LABEL"
  done
  # A closed input, rather than a blank answer, leaves the prompt unterminated.
  printf '\n'
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  -*) printf 'Unknown option: %s\n' "$1" >&2; exit 2 ;;
esac

for path in "$@"; do
  remember_target "$path"
done

# The two agents hard-code where they look, and neither reads a plain
# ~/AGENTS.md; link_config creates the directory when the tool is not installed
# here yet, so the file is in place the moment it is.
link_config "$FILE" "$HOME/.claude/CLAUDE.md"
link_config "$FILE" "$HOME/.codex/AGENTS.md"

if [ "$#" -eq 0 ] && [ -t 0 ] && [ -t 1 ]; then
  prompt_for_targets
fi

while IFS= read -r target; do
  link_config "$FILE" "$(expand_path "$target")"
done < <(read_targets)
