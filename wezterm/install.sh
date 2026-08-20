#!/usr/bin/env bash
# Install WezTerm on macOS and link its configuration.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LABEL=wezterm
source "$DIR/../install-lib.sh"
require_no_args "$@"

case "$(uname -s)" in
  Darwin)
    if has brew && brew list --cask wezterm >/dev/null 2>&1; then
      log 'Already installed'
    else
      brew_install --cask wezterm
    fi
    ;;
  Linux) log 'The Homebrew WezTerm cask is macOS-only; install WezTerm manually on Linux.' ;;
  *) log 'Only macOS and Linux are supported.'; exit 1 ;;
esac

link_config "$DIR/.wezterm.lua" "$HOME/.wezterm.lua"
