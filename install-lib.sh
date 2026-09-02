#!/usr/bin/env bash

# Print messages with the name of the component that is currently running.
log() {
  printf '[%s] %s\n' "$LABEL" "$*"
}

# Return success when an executable is available on PATH.
has() {
  command -v "$1" >/dev/null 2>&1
}

# Keep Homebrew's executables ahead of the operating-system versions in future
# shells. Homebrew may be available to this installer through an inherited PATH
# even when a fresh login shell would not find it.
persist_brew_shellenv() {
  local brew_path profile source_line
  brew_path="$(command -v brew)"

  case "${SHELL:-}" in
    */zsh) profile="$HOME/.zprofile" ;;
    */bash)
      case "$(uname -s)" in
        Darwin) profile="$HOME/.bash_profile" ;;
        *) profile="$HOME/.bashrc" ;;
      esac
      ;;
    *)
      log "Homebrew is installed, but ${SHELL:-the current shell} is not supported for automatic PATH setup."
      return
      ;;
  esac

  source_line="eval \"\$($brew_path shellenv)\""
  if [ -f "$profile" ] && grep -Fq "$source_line" "$profile"; then
    return
  fi

  if [ -s "$profile" ]; then
    printf '\n' >> "$profile"
  fi
  printf '%s\n%s\n' \
    '# Homebrew environment (managed by the dotfiles installer)' \
    "$source_line" >> "$profile"
  log "Enabled Homebrew in future shells via $profile"
}

# Component installers take no options; keep their command-line interface strict.
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

  persist_brew_shellenv

  local kind_flag=--formula

  if [ "${1:-}" = --cask ]; then
    kind_flag=--cask
    shift
  fi

  local package outdated outdated_status
  for package in "$@"; do
    # `brew list` checks the local installation receipt without installing anything.
    if ! brew list "$kind_flag" "$package" >/dev/null 2>&1; then
      log "Installing $package"
      brew install "$kind_flag" "$package"
      continue
    fi

    # Homebrew exits 1 when a specifically named package is outdated, so preserve
    # both its output and status instead of treating every non-zero status as an error.
    outdated=''
    if outdated="$(brew outdated --quiet "$kind_flag" "$package")"; then
      outdated_status=0
    else
      outdated_status=$?
    fi

    if [ "$outdated_status" -gt 1 ] || { [ "$outdated_status" -eq 1 ] && [ -z "$outdated" ]; }; then
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

# Point a standard config location at a file or directory in this repository.
# Preserve a user's real file/directory as a timestamped backup before replacing it.
link_config() {
  local source=$1 target=$2
  mkdir -p "$(dirname "$target")"

  # An exact existing link needs no work and, importantly, no new backup.
  if [ -L "$target" ] && [ "$(readlink "$target")" = "$source" ]; then
    log "Already linked $target"
    return
  fi

  # Back up only real files/directories. `ln -sfn` safely replaces other symlinks.
  if [ -e "$target" ] && [ ! -L "$target" ]; then
    local backup="${target}.bak.$(date +%s)"
    log "Backing up $target to $backup"
    mv "$target" "$backup"
  fi

  log "Linking $target"
  ln -sfn "$source" "$target"
}
