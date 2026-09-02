#!/usr/bin/env bash
# Install Neovim and link its configuration.
# Stop immediately if an installation or linking step fails.
set -euo pipefail

# Load shared helpers; LABEL prefixes their messages with this component's name.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LABEL=nvim
source "$DIR/../install-lib.sh"
require_no_args "$@"

# Install Neovim plus the command-line tools used by this configuration.
case "$(uname -s)" in
  Darwin)
    brew_install neovim ripgrep fd node python lazygit
    # The Nerd Font supplies the extra glyphs used by the configuration's icons.
    brew_install --cask font-jetbrains-mono-nerd-font
    # Treesitter parsers need Apple's compiler toolchain.
    # If it is absent, macOS opens the Command Line Tools installer.
    xcode-select -p >/dev/null 2>&1 || xcode-select --install
    ;;
  Linux)
    brew_install neovim ripgrep fd node python lazygit
    ;;
  *) log 'Only macOS and Linux are supported.'; exit 1 ;;
esac

# Neovim discovers its configuration at ~/.config/nvim.
link_config "$DIR" "$HOME/.config/nvim"
log 'Run nvim to finish plugin setup.'
