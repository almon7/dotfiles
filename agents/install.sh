#!/usr/bin/env bash
# Give every coding agent the same personal instructions.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LABEL=agents
source "$DIR/../install-lib.sh"

FILE="$DIR/AGENTS.md"

usage() {
  printf 'Usage: %s\n' "$0"
  printf 'Links AGENTS.md to the paths Claude Code and Codex read.\n'
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  '') ;;
  *) printf 'Unexpected argument: %s\n' "$1" >&2; exit 2 ;;
esac

# The two agents hard-code where they look, and neither reads a plain
# ~/AGENTS.md; link_config creates the directory when the tool is not installed
# here yet, so the file is in place the moment it is.
link_config "$FILE" "$HOME/.claude/CLAUDE.md"
link_config "$FILE" "$HOME/.codex/AGENTS.md"
