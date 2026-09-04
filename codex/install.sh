#!/usr/bin/env bash
# Make the Git-tracked personal skills available to Codex.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LABEL=codex
source "$DIR/../install-lib.sh"
require_no_args "$@"

link_config "$DIR/skills" "$HOME/.agents/skills"
