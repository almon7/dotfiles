#!/usr/bin/env bash
# Install WezTerm on macOS and link its configuration.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LABEL=wezterm
source "$DIR/../install-lib.sh"
require_no_args "$@"

case "$(uname -s)" in
  Darwin) brew_install --cask wezterm ;;
  Linux) log 'The Homebrew WezTerm cask is macOS-only; install WezTerm manually on Linux.' ;;
  *) log 'Only macOS and Linux are supported.'; exit 1 ;;
esac

link_config "$DIR/.wezterm.lua" "$HOME/.wezterm.lua"
