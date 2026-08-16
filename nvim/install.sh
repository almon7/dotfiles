#!/usr/bin/env bash
# Install Neovim and link its configuration.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LABEL=nvim
source "$DIR/../install-lib.sh"
require_no_args "$@"

case "$(uname -s)" in
  Darwin)
    brew_install neovim ripgrep fd node python
    brew_install --cask font-jetbrains-mono-nerd-font
    xcode-select -p >/dev/null 2>&1 || xcode-select --install
    ;;
  Linux)
    brew_install neovim ripgrep fd node python
    ;;
  *) log 'Only macOS and Linux are supported.'; exit 1 ;;
esac

link_config "$DIR" "$HOME/.config/nvim"
log 'Run nvim to finish plugin setup.'
