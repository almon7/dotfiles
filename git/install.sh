#!/usr/bin/env bash
# Install Git and configure machine-wide Git defaults.
set -uo pipefail

DESCRIPTION="Git package, Neovim editor, and identity check"
[ "${1:-}" = "--description" ] && { printf '%s\n' "$DESCRIPTION"; exit 0; }

CONFIG_ONLY=false
case "${1:-}" in
  --config-only) CONFIG_ONLY=true ;;
  '') ;;
  -h|--help) printf 'Usage: %s [--config-only]\n' "$0"; exit 0 ;;
  *) printf 'Unknown option: %s\n' "$1" >&2; exit 2 ;;
esac

PACKAGE_FAILED=false
log() { printf '\033[1;34m[git]\033[0m %s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }
package_failed() {
  PACKAGE_FAILED=true
  log "Package error: $*"
}

install_package() {
  have git && return
  case "$(uname -s)" in
    Darwin)
      if have brew; then
        log "Installing Git"
        brew install git || package_failed "Homebrew could not install Git."
      else
        package_failed "Homebrew not found; the Git package was skipped."
      fi
      ;;
    Linux)
      if ! have apt-get; then
        package_failed "No apt-get found; the Git package was skipped."
        return
      fi
      sudo_cmd=""
      if [ "$(id -u)" -ne 0 ]; then
        if ! have sudo; then package_failed "Not root and no sudo; the Git package was skipped."; return; fi
        if ! sudo -n true 2>/dev/null; then
          if [ ! -t 0 ]; then package_failed "sudo needs a terminal; the Git package was skipped."; return; fi
          log "Elevated permissions needed to install Git."
          if ! sudo -v; then package_failed "sudo authorization failed; the Git package was skipped."; return; fi
        fi
        sudo_cmd=sudo
      fi
      log "Installing Git"
      if ! { $sudo_cmd apt-get update -y && $sudo_cmd apt-get install -y git; }; then
        package_failed "apt could not install Git."
      fi
      ;;
    *) package_failed "Unsupported OS; the Git package was skipped." ;;
  esac
}

$CONFIG_ONLY || install_package

if have git; then
  log "Setting Git's editor to nvim"
  git config --global core.editor nvim || exit 1
  if ! git config --global --get user.name >/dev/null 2>&1 ||
     ! git config --global --get user.email >/dev/null 2>&1; then
    log "Warning: Git identity is incomplete. Set user.name and user.email before committing."
  fi
elif $CONFIG_ONLY; then
  log "Git is not installed; editor and identity configuration were skipped."
  exit 1
fi

if $PACKAGE_FAILED; then
  log "Installer incomplete: the Git package failed."
  exit 1
fi
log "Done."
