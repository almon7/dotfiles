#!/usr/bin/env bash
# Install WezTerm on macOS and link this folder's configuration.
set -uo pipefail

DESCRIPTION="WezTerm and ~/.wezterm.lua"
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
log() { printf '\033[1;34m[wezterm]\033[0m %s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }
package_failed() {
  PACKAGE_FAILED=true
  log "Package error: $*"
}

install_packages() {
  case "$(uname -s)" in
    Darwin)
      have wezterm && return
      if ! have brew; then
        package_failed "Homebrew not found; the WezTerm package was skipped."
        return
      fi
      log "Installing WezTerm"
      brew install --cask wezterm || package_failed "Homebrew could not install WezTerm."
      ;;
    Linux)
      have wezterm || log "WezTerm package install is not automated on Linux; install it for your distribution."
      ;;
    *) log "Unsupported OS; skipping the WezTerm package." ;;
  esac
}

$CONFIG_ONLY || install_packages

if [ -e "$HOME/.wezterm.lua" ] && [ ! -L "$HOME/.wezterm.lua" ]; then
  backup="$HOME/.wezterm.lua.bak.$(date +%s)"
  log "Backing up existing ~/.wezterm.lua to $backup"
  mv "$HOME/.wezterm.lua" "$backup" || exit 1
fi
log "Linking ~/.wezterm.lua -> $DIR/.wezterm.lua"
ln -sfn "$DIR/.wezterm.lua" "$HOME/.wezterm.lua" || exit 1
if $PACKAGE_FAILED; then
  log "Config installed, but the WezTerm package failed."
  exit 1
fi
log "Done."
