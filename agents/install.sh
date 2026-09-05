#!/usr/bin/env bash
# Give every coding agent the same personal instructions.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LABEL=agents
source "$DIR/../install-lib.sh"
require_no_args "$@"

# Each agent hard-codes where it looks, so one file is linked to both names.
link_config "$DIR/AGENTS.md" "$HOME/.claude/CLAUDE.md"
link_config "$DIR/AGENTS.md" "$HOME/.codex/AGENTS.md"
