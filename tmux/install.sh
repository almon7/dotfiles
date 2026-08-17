#!/usr/bin/env bash
# Install tmux and link its configuration.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LABEL=tmux
source "$DIR/../install-lib.sh"
require_no_args "$@"

case "$(uname -s)" in
  Darwin|Linux) brew_install tmux ;;
  *) log 'Only macOS and Linux are supported.'; exit 1 ;;
esac

has git || brew_install git

TPM_DIR="$HOME/.tmux/plugins/tpm"
if [ ! -d "$TPM_DIR/.git" ]; then
  log 'Installing tmux plugin manager'
  git clone --depth 1 https://github.com/tmux-plugins/tpm "$TPM_DIR"
else
  log 'tmux plugin manager is already installed'
fi

link_config "$DIR/tmux.conf" "$HOME/.tmux.conf"

log 'Inside tmux, press C-a I to install the persistence plugins'
