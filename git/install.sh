#!/usr/bin/env bash
# Install Git and make Neovim its default editor.
set -euo pipefail

LABEL=git
source "$(dirname "${BASH_SOURCE[0]}")/../install-lib.sh"
require_no_args "$@"

if ! has git; then
  case "$(uname -s)" in
    Darwin) brew install git ;;
    Linux) apt_install git ;;
    *) log 'Only macOS and Linux are supported.'; exit 1 ;;
  esac
fi

if has git; then
  if [ "$(git config --global --get core.editor || true)" != nvim ]; then
    git config --global core.editor nvim
  fi
  if ! git config --global user.name >/dev/null ||
     ! git config --global user.email >/dev/null; then
    log 'Set user.name and user.email before committing.'
  fi
else
  log 'Git is not installed; skipping its configuration.'
fi
