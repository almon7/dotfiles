#!/usr/bin/env bash

log() {
  printf '[%s] %s\n' "$LABEL" "$*"
}

has() {
  command -v "$1" >/dev/null 2>&1
}

parse_args() {
  CONFIG_ONLY=false
  case "${1:-}" in
    --config-only) CONFIG_ONLY=true ;;
    '') ;;
    -h|--help) printf 'Usage: %s [--config-only]\n' "$0"; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; exit 2 ;;
  esac
}

apt_install() {
  if ! has apt-get; then
    log 'apt-get is required on Linux.'
    return 1
  fi

  as_root apt-get update
  as_root apt-get install -y "$@"
}

as_root() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  else
    sudo "$@"
  fi
}

link_config() {
  local source=$1 target=$2
  mkdir -p "$(dirname "$target")"

  if [ -e "$target" ] && [ ! -L "$target" ]; then
    local backup="${target}.bak.$(date +%s)"
    log "Backing up $target to $backup"
    mv "$target" "$backup"
  fi

  log "Linking $target"
  ln -sfn "$source" "$target"
}
