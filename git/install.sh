#!/usr/bin/env bash
# Install Git and make Neovim its default editor.
# Stop immediately if an installation or configuration step fails.
set -euo pipefail

# Load shared helpers; LABEL prefixes their messages with this component's name.
LABEL=git
source "$(dirname "${BASH_SOURCE[0]}")/../install-lib.sh"
require_no_args "$@"

# Git is distributed as a Homebrew formula on both supported platforms.
case "$(uname -s)" in
  Darwin|Linux) brew_install git ;;
  *) log 'Only macOS and Linux are supported.'; exit 1 ;;
esac

# Avoid rewriting global configuration when it already has the desired value.
if has git; then
  if [ "$(git config --global --get core.editor || true)" != nvim ]; then
    git config --global core.editor nvim
  fi
  if ! git config --global user.name >/dev/null ||
     ! git config --global user.email >/dev/null; then
    # Identity is personal machine state, so warn instead of inventing values.
    log 'Set user.name and user.email before committing.'
  fi
else
  log 'Git is not installed; skipping its configuration.'
fi
