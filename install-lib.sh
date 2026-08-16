#!/usr/bin/env bash

log() {
  printf '[%s] %s\n' "$LABEL" "$*"
}

has() {
  command -v "$1" >/dev/null 2>&1
}

require_no_args() {
  case "${1:-}" in
    '') ;;
    -h|--help) printf 'Usage: %s\n' "$0"; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; exit 2 ;;
  esac
}

brew_install() {
  if ! has brew; then
    log 'Homebrew is required. Install it from https://brew.sh and run this installer again.'
    return 1
  fi

  brew install "$@"
}

link_config() {
  local source=$1 target=$2
  mkdir -p "$(dirname "$target")"

  if [ -L "$target" ] && [ "$(readlink "$target")" = "$source" ]; then
    log "Already linked $target"
    return
  fi

  if [ -e "$target" ] && [ ! -L "$target" ]; then
    local backup="${target}.bak.$(date +%s)"
    log "Backing up $target to $backup"
    mv "$target" "$backup"
  fi

  log "Linking $target"
  ln -sfn "$source" "$target"
}
