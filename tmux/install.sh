#!/usr/bin/env bash
# Install tmux and link this folder's configuration.
set -uo pipefail

DESCRIPTION="tmux package and ~/.tmux.conf"
[ "${1:-}" = "--description" ] && { printf '%s\n' "$DESCRIPTION"; exit 0; }

CONFIG_ONLY=false
case "${1:-}" in
  --config-only) CONFIG_ONLY=true ;;
  '') ;;
  -h|--help) printf 'Usage: %s [--config-only]\n' "$0"; exit 0 ;;
  *) printf 'Unknown option: %s\n' "$1" >&2; exit 2 ;;
esac

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_FAILED=false
log() { printf '\033[1;34m[tmux]\033[0m %s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }
package_failed() {
  PACKAGE_FAILED=true
  log "Package error: $*"
}

install_package() {
  have tmux && return
  case "$(uname -s)" in
    Darwin)
      if have brew; then
        log "Installing tmux"
        brew install tmux || package_failed "Homebrew could not install tmux."
      else
        package_failed "Homebrew not found; the tmux package was skipped."
      fi
      ;;
    Linux)
      if ! have apt-get; then
        package_failed "No apt-get found; the tmux package was skipped."
        return
      fi
      sudo_cmd=""
      if [ "$(id -u)" -ne 0 ]; then
        if ! have sudo; then package_failed "Not root and no sudo; the tmux package was skipped."; return; fi
        if ! sudo -n true 2>/dev/null; then
          if [ ! -t 0 ]; then package_failed "sudo needs a terminal; the tmux package was skipped."; return; fi
          log "Elevated permissions needed to install tmux."
          if ! sudo -v; then package_failed "sudo authorization failed; the tmux package was skipped."; return; fi
        fi
        sudo_cmd=sudo
      fi
      log "Installing tmux"
      if ! { $sudo_cmd apt-get update -y && $sudo_cmd apt-get install -y tmux; }; then
        package_failed "apt could not install tmux."
      fi
      ;;
    *) log "Unsupported OS; skipping the tmux package." ;;
  esac
}

$CONFIG_ONLY || install_package

if [ -e "$HOME/.tmux.conf" ] && [ ! -L "$HOME/.tmux.conf" ]; then
  backup="$HOME/.tmux.conf.bak.$(date +%s)"
  log "Backing up existing ~/.tmux.conf to $backup"
  mv "$HOME/.tmux.conf" "$backup" || exit 1
fi
log "Linking ~/.tmux.conf -> $DIR/tmux.conf"
ln -sfn "$DIR/tmux.conf" "$HOME/.tmux.conf" || exit 1
if $PACKAGE_FAILED; then
  log "Config installed, but the tmux package failed."
  exit 1
fi
log "Done. Start tmux or reload with prefix + r."
