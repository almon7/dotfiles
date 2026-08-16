#!/usr/bin/env bash
# Install WezTerm on macOS and link its configuration.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LABEL=wezterm
source "$DIR/../install-lib.sh"
parse_args "$@"

if ! $CONFIG_ONLY && ! has wezterm; then
  case "$(uname -s)" in
    Darwin) brew install --cask wezterm ;;
    Linux) log 'Install WezTerm with your distribution package manager.' ;;
    *) log 'Only macOS and Linux are supported.'; exit 1 ;;
  esac
fi

link_config "$DIR/.wezterm.lua" "$HOME/.wezterm.lua"
