#!/usr/bin/env bash
# Install Neovim and link its configuration.
# Stop immediately if an installation or linking step fails.
set -euo pipefail    # abort on an error, an unset variable, or a failing pipeline stage

# Load shared helpers; LABEL prefixes their messages with this component's name.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"    # absolute path of this script's directory
LABEL=nvim    # the tag log() puts in front of every message
source "$DIR/../install-lib.sh"    # pull in log, brew_install, link_config, ...
require_no_args "$@"    # reject anything but an empty argument list or --help

# Install Neovim plus the command-line tools used by this configuration.
case "$(uname -s)" in    # branch on the kernel name
  Darwin)
    brew_install neovim ripgrep fd node python lazygit    # the editor and the tools it shells out to
    # The Nerd Font supplies the extra glyphs used by the configuration's icons.
    brew_install --cask font-jetbrains-mono-nerd-font    # fonts ship as casks, not formulas
    # Treesitter parsers need Apple's compiler toolchain.
    # If it is absent, macOS opens the Command Line Tools installer.
    xcode-select -p >/dev/null 2>&1 || xcode-select --install    # succeeds quietly once they are present
    ;;
  Linux)
    brew_install neovim ripgrep fd node python lazygit    # no font or toolchain step needed here
    ;;
  *) log 'Only macOS and Linux are supported.'; exit 1 ;;    # anything else is unsupported
esac

# The tools above are only kept current where Homebrew owns them; a copy
# installed another way keeps running its own version.
for command_name in nvim rg fd node lazygit; do    # the commands worth checking
  warn_if_shadowed "$command_name"    # report one that resolves outside Homebrew
done

# Neovim discovers its configuration at ~/.config/nvim.
link_config "$DIR" "$HOME/.config/nvim"    # the whole component directory is the config
# lazy.nvim installs missing plugins on the next start and holds the rest at the
# versions in lazy-lock.json, so upgrading them stays a deliberate step.
log 'Run nvim to finish plugin setup; use :Lazy update to move the pinned versions.'
