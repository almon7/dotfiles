#!/usr/bin/env bash
# Render the active model and used context from Claude Code's status-line JSON.
set -euo pipefail

jq -r '"[\(.model.display_name // .model.id // "unknown model")] \((.context_window.used_percentage // 0) | floor)% context"'
