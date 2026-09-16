#!/usr/bin/env bash
# Install the Claude Code provider wrapper and status-line configuration.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LABEL=claude
source "$DIR/../install-lib.sh"
require_no_args "$@"

# The status line parses the JSON Claude Code sends it with jq.
case "$(uname -s)" in
Darwin | Linux) brew_install jq ;;
*)
	log 'Only macOS and Linux are supported.'
	exit 1
	;;
esac

link_config "$DIR/claude-ds" "$HOME/.local/bin/claude-ds"
link_config "$DIR/statusline.sh" "$HOME/.claude/statusline.sh"

DESIRED="$DIR/settings.json"
ACTUAL="$HOME/.claude/settings.json"

if [ ! -f "$ACTUAL" ]; then
	log "Creating $ACTUAL"
	printf '{}\n' >"$ACTUAL"
fi

if ! jq -e -s 'length == 1 and (.[0] | type == "object")' "$ACTUAL" >/dev/null 2>&1; then
	log "$ACTUAL does not contain exactly one JSON object; leaving it alone"
	exit 1
fi

if jq -e 'has("statusLine")' "$ACTUAL" >/dev/null; then
	if jq -e --slurpfile desired "$DESIRED" '.statusLine == $desired[0].statusLine' "$ACTUAL" >/dev/null; then
		log 'statusLine is already configured'
	else
		log "statusLine is already set differently in $ACTUAL; leaving it alone"
	fi
else
	TEMP="$ACTUAL.dotfiles-tmp.$$"
	jq --slurpfile desired "$DESIRED" '.statusLine = $desired[0].statusLine' "$ACTUAL" >"$TEMP"
	cat "$TEMP" >"$ACTUAL"
	rm -f "$TEMP"
	log "Added statusLine to $ACTUAL"
fi

has claude || log 'Claude Code itself is not installed; the wrapper and status line are ready for it.'
case ":$PATH:" in
*":$HOME/.local/bin:"*) ;;
*) log "$HOME/.local/bin is not on PATH; add it before using claude-ds." ;;
esac
