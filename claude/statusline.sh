#!/usr/bin/env bash
# Render the active model, reasoning effort, working directory, git branch and
# used context from Claude Code's status-line JSON, which arrives on stdin.
set -euo pipefail

input=$(cat)
dir=$(jq -r '.workspace.current_dir // .cwd // ""' <<<"$input")

# The status-line JSON carries no branch, so ask git about the directory it reports.
branch=""
if [ -n "$dir" ]; then
	# An inherited GIT_DIR would answer for a different repository than the one shown.
	unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE
	branch=$(git -C "$dir" branch --show-current 2>/dev/null || true)
fi

# Shorten the home directory and the paths under it. A sibling that merely shares
# the prefix, such as /home/ubuntu2, is not under home and keeps its full path.
display_dir="$dir"
if [ -n "${HOME:-}" ]; then
	case "$dir" in
	"$HOME") display_dir="~" ;;
	"$HOME"/*) display_dir="~${dir#"$HOME"}" ;;
	esac
fi

jq -r --arg dir "$display_dir" --arg branch "$branch" '
    "[\(.model.display_name? // .model.id? // "unknown model")]"
    + (if (.effort.level? // null) then " · \(.effort.level)" else "" end)
    + (if $dir == "" then "" else " · \($dir)" end)
    + (if $branch == "" then "" else " · \($branch)" end)
    + " · \((.context_window.used_percentage? // 0) | floor)% context"
' <<<"$input"
