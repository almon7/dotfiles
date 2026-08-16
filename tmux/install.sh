#!/usr/bin/env bash
# Install tmux and link its configuration.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LABEL=tmux
source "$DIR/../install-lib.sh"
require_no_args "$@"

if ! has tmux; then
  case "$(uname -s)" in
    Darwin) brew install tmux ;;
    Linux) apt_install tmux ;;
    *) log 'Only macOS and Linux are supported.'; exit 1 ;;
  esac
fi

link_config "$DIR/tmux.conf" "$HOME/.tmux.conf"
