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

# Bring each requested Homebrew package to the desired state:
# install it when missing, upgrade it when outdated, or leave it alone when current.
# Pass --cask first for graphical applications and fonts; formulas are the default.
brew_install() {
  if ! has brew; then
    log 'Homebrew is required. Install it from https://brew.sh and run this installer again.'
    return 1
  fi

  local kind_flag=--formula

  if [ "${1:-}" = --cask ]; then
    kind_flag=--cask
    shift
  fi

  local package outdated
  for package in "$@"; do
    # `brew list` checks the local installation receipt without installing anything.
    if ! brew list "$kind_flag" "$package" >/dev/null 2>&1; then
      log "Installing $package"
      brew install "$kind_flag" "$package"
      continue
    fi

    # Ask Homebrew whether the installed receipt is older than its current metadata.
    if ! outdated="$(brew outdated --quiet "$kind_flag" "$package")"; then
      log "Could not check whether $package is outdated."
      return 1
    fi

    if [ -n "$outdated" ]; then
      log "Upgrading $package"
      brew upgrade "$kind_flag" "$package"
    else
      log "$package is already up to date"
    fi
  done
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
