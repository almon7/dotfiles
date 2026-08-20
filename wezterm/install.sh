#!/usr/bin/env bash
# Install WezTerm on macOS and link its configuration.
# Stop immediately if an installation or linking step fails.
set -euo pipefail

# Load shared helpers; LABEL prefixes their messages with this component's name.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LABEL=wezterm
source "$DIR/../install-lib.sh"
require_no_args "$@"

# Homebrew's WezTerm cask is macOS-only. Linux still receives the config link below.
case "$(uname -s)" in
  Darwin) brew_install --cask wezterm ;;
  Linux) log 'The Homebrew WezTerm cask is macOS-only; install WezTerm manually on Linux.' ;;
  *) log 'Only macOS and Linux are supported.'; exit 1 ;;
esac

# WezTerm reads this file directly from the user's home directory.
link_config "$DIR/.wezterm.lua" "$HOME/.wezterm.lua"
