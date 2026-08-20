#!/usr/bin/env bash
# Install tmux and link its configuration.
# Stop immediately if an installation, clone, or linking step fails.
set -euo pipefail

# Load shared helpers; LABEL prefixes their messages with this component's name.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LABEL=tmux
source "$DIR/../install-lib.sh"
require_no_args "$@"

# Install tmux itself from Homebrew on either supported platform.
case "$(uname -s)" in
  Darwin|Linux) brew_install tmux ;;
  *) log 'Only macOS and Linux are supported.'; exit 1 ;;
esac

# Git is needed for the plugin-manager checkout, even when tmux is installed alone.
has git || brew_install git

TPM_DIR="$HOME/.tmux/plugins/tpm"
# Clone TPM once. An existing Git checkout is left untouched on later runs.
if [ ! -d "$TPM_DIR/.git" ]; then
  log 'Installing tmux plugin manager'
  git clone --depth 1 https://github.com/tmux-plugins/tpm "$TPM_DIR"
else
  log 'tmux plugin manager is already installed'
fi

# tmux reads its per-user configuration from ~/.tmux.conf.
link_config "$DIR/tmux.conf" "$HOME/.tmux.conf"

log 'Inside tmux, press C-a I to install the persistence plugins'
