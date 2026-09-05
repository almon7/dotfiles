#!/usr/bin/env bash

# Print messages with the name of the component that is currently running.
log() {
  printf '[%s] %s\n' "$LABEL" "$*"
}

# Return success when an executable is available on PATH.
has() {
  command -v "$1" >/dev/null 2>&1
}

# Delete a fixed-size block that an earlier version of this installer appended,
# so the managed block written below replaces it instead of joining it.
remove_legacy_lines() {
  local file=$1 marker=$2 count=$3 temp

  [ -f "$file" ] || return 0
  grep -Fqx "$marker" "$file" || return 0

  temp="$file.dotfiles-tmp.$$"
  awk -v marker="$marker" -v count="$count" '
    skip > 0 { skip--; next }
    $0 == marker { skip = count - 1; next }
    { print }
  ' "$file" > "$temp"
  # Copy the contents back so the original file keeps its permissions.
  cat "$temp" > "$file"
  rm -f "$temp"
}

# Keep one delimited block of lines in a shell start-up file. Rewrite the block
# whenever its contents change, so a rerun after something moves - a new
# Homebrew prefix, a new WezTerm location - updates the file in place instead of
# appending a second, contradictory copy.
write_managed_block() {
  local file=$1 name=$2
  shift 2

  local begin="# >>> $name (managed by the dotfiles installer) >>>"
  local end="# <<< $name (managed by the dotfiles installer) <<<"
  local desired existing temp action=Enabled

  desired="$(printf '%s\n' "$begin" "$@" "$end")"

  if [ -f "$file" ] && grep -Fqx "$begin" "$file"; then
    existing="$(awk -v begin="$begin" -v end="$end" '
      $0 == begin { inside = 1 }
      inside { print }
      $0 == end { inside = 0 }
    ' "$file")"

    if [ "$existing" = "$desired" ]; then
      return 0
    fi

    temp="$file.dotfiles-tmp.$$"
    awk -v begin="$begin" -v end="$end" '
      $0 == begin { skipping = 1 }
      !skipping { print }
      $0 == end { skipping = 0 }
    ' "$file" > "$temp"
    cat "$temp" > "$file"
    rm -f "$temp"
    action=Updated
  fi

  # Separate the block from the surrounding file, without stacking up blank
  # lines each time the block is rewritten.
  if [ -s "$file" ] && [ -n "$(tail -n 1 "$file")" ]; then
    printf '\n' >> "$file"
  fi
  printf '%s\n' "$desired" >> "$file"
  log "$action $name in $file"
}

# Keep Homebrew's executables ahead of the operating-system versions in future
# shells. Homebrew may be available to this installer through an inherited PATH
# even when a fresh login shell would not find it.
BREW_SHELLENV_HANDLED=${BREW_SHELLENV_HANDLED:-0}
persist_brew_shellenv() {
  local brew_path profile

  # Several components install packages, and the answer cannot change during one
  # run; check the start-up file once instead of once per package list.
  if [ "$BREW_SHELLENV_HANDLED" -eq 1 ]; then
    return 0
  fi
  BREW_SHELLENV_HANDLED=1

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

  remove_legacy_lines "$profile" \
    '# Homebrew environment (managed by the dotfiles installer)' 2
  write_managed_block "$profile" 'Homebrew environment' \
    "eval \"\$($brew_path shellenv)\""
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

# Install a graphical application from a cask, unless the user installed the same
# application by hand. A manual copy occupies the same /Applications destination,
# so the cask would fail with "It seems there is already an App at ...".
brew_install_app() {
  local app=$1 cask=$2

  if [ -d "/Applications/$app.app" ] && ! brew list --cask "$cask" >/dev/null 2>&1; then
    log "$app is already installed outside Homebrew; leaving it in place"
    return 0
  fi

  brew_install --cask "$cask"
}

# Report a copy of a command that this installer cannot keep current: a program
# installed by hand, or by another package manager, still wins the PATH lookup
# and goes on running its own older version after Homebrew upgrades ours.
warn_if_shadowed() {
  local command_name=$1 active brew_prefix brew_copy

  has brew || return 0
  has "$command_name" || return 0

  brew_prefix="$(brew --prefix 2>/dev/null)" || return 0
  if [ -z "$brew_prefix" ]; then
    return 0
  fi

  brew_copy="$brew_prefix/bin/$command_name"
  if [ ! -x "$brew_copy" ]; then
    return 0
  fi

  active="$(command -v "$command_name")"
  if [ "$active" = "$brew_copy" ]; then
    return 0
  fi

  log "$command_name runs from $active, which this installer does not update."
  log "Homebrew's copy is $brew_copy; put $brew_prefix/bin earlier on PATH to use it."
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

  # Back up anything else that is already there, including a link to a different
  # location and a link whose target is missing: both may be the user's own
  # configuration, and replacing them outright would leave no way back.
  if [ -e "$target" ] || [ -L "$target" ]; then
    local backup="${target}.bak.$(date +%s)"
    log "Backing up $target to $backup"
    mv "$target" "$backup"
  fi

  log "Linking $target"
  ln -sfn "$source" "$target"
}
