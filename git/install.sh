#!/usr/bin/env bash
# Install Git, choose an identity mode, and optionally enroll the personal SSH key.
# Stop immediately if an installation or configuration step fails.
set -euo pipefail

# Load shared helpers; LABEL prefixes their messages with this component's name.
LABEL=git
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../install-lib.sh"
require_no_args "$@"

PROFILES_CONFIG="$DIR/gitconfig"
GLOBAL_CONFIG="$DIR/gitconfig-global"
PERSONAL_CONFIG="$DIR/gitconfig-personal"

# Git is distributed as a Homebrew formula on both supported platforms.
case "$(uname -s)" in
  Darwin|Linux) brew_install git ;;
  *) log 'Only macOS and Linux are supported.'; exit 1 ;;
esac

choose_git_mode() {
  local requested=${DOTFILES_GIT_MODE:-} current_target='' default_mode choice

  if [ -n "$requested" ]; then
    case "$requested" in
      profiles|global|skip) GIT_MODE=$requested; return ;;
      *) log "DOTFILES_GIT_MODE must be profiles, global, or skip; got: $requested"; exit 2 ;;
    esac
  fi

  if [ -L "$HOME/.gitconfig" ]; then
    current_target="$(readlink "$HOME/.gitconfig")"
    case "$current_target" in
      "$PROFILES_CONFIG") GIT_MODE=profiles; return ;;
      "$GLOBAL_CONFIG") GIT_MODE=global; return ;;
    esac
  fi

  # Never replace an unknown existing configuration or wait for input during an
  # automated run. Automation can opt in with DOTFILES_GIT_MODE.
  if [ ! -t 0 ] || [ ! -t 1 ]; then
    GIT_MODE=skip
    return
  fi

  if [ -e "$HOME/.gitconfig" ] || [ -L "$HOME/.gitconfig" ]; then
    default_mode=skip
  else
    default_mode=profiles
  fi

  while true; do
    printf '\nGit identity setup\n\n'
    printf '  1) Directory profiles — personal only in ~/dotfiles and ~/code/personal\n'
    printf '  2) Personal globally — use almon7 for every repository by default\n'
    printf '  3) Skip — preserve the existing Git configuration\n\n'
    printf 'Choose 1, 2, or 3 [%s]: ' "$default_mode"

    choice=''
    if ! IFS= read -r choice; then
      GIT_MODE=skip
      return
    fi

    case "$choice" in
      1|profiles) GIT_MODE=profiles; return ;;
      2|global) GIT_MODE=global; return ;;
      3|skip) GIT_MODE=skip; return ;;
      '') GIT_MODE=$default_mode; return ;;
      *) log 'Choose 1, 2, or 3.' ;;
    esac
  done
}

has git || { log 'Git is not installed; skipping its configuration.'; exit 0; }
choose_git_mode

case "$GIT_MODE" in
  skip)
    log 'Leaving Git identity and GitHub authentication unchanged'
    ;;
  profiles|global)
    link_config "$PERSONAL_CONFIG" "$HOME/.gitconfig-personal"
    if [ "$GIT_MODE" = profiles ]; then
      link_config "$PROFILES_CONFIG" "$HOME/.gitconfig"
      mkdir -p "$HOME/code/personal"
      log 'Using directory-based Git profiles'
    else
      link_config "$GLOBAL_CONFIG" "$HOME/.gitconfig"
      log 'Using the personal Git profile globally'
    fi

    if [ -t 0 ] && [ -t 1 ]; then
      "$DIR/setup-accounts.sh"
    elif [ -f "$HOME/.ssh/id_ed25519_personal" ]; then
      "$DIR/setup-accounts.sh"
    else
      log 'Skipping SSH-key creation in this unattended run'
    fi
    ;;
esac
