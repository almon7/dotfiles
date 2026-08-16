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

link_config "$DIR/tmux.conf" "$HOME/.tmux.conf"
