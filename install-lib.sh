#!/usr/bin/env bash

# Print messages with the name of the component that is currently running.
log() {
  printf '[%s] %s\n' "$LABEL" "$*"    # "$*" joins every argument into one message
}

# Return success when an executable is available on PATH.
has() {
  command -v "$1" >/dev/null 2>&1    # the path itself is not wanted, only the exit status
}

# Delete a fixed-size block that an earlier version of this installer appended,
# so the managed block written below replaces it instead of joining it.
remove_legacy_lines() {
  local file=$1 marker=$2 count=$3 temp    # the file, its first line, and how many lines the block spans

  [ -f "$file" ] || return 0    # nothing to clean out of a file that is not there
  grep -Fqx "$marker" "$file" || return 0    # -Fx demands a literal, whole-line match

  temp="$file.dotfiles-tmp.$$"    # $$ keeps concurrent runs off each other's file
  awk -v marker="$marker" -v count="$count" '
    skip > 0 { skip--; next }    # drop the lines that follow the marker
    $0 == marker { skip = count - 1; next }    # drop the marker and arm the counter
    { print }    # everything else survives
  ' "$file" > "$temp"
  # Copy the contents back so the original file keeps its permissions.
  cat "$temp" > "$file"    # a mv would replace the inode, and its mode with it
  rm -f "$temp"
}

# Keep one delimited block of lines in a shell start-up file. Rewrite the block
# whenever its contents change, so a rerun after something moves - a new
# Homebrew prefix, a new WezTerm location - updates the file in place instead of
# appending a second, contradictory copy.
write_managed_block() {
  local file=$1 name=$2    # the start-up file and the block's title
  shift 2    # what remains in "$@" is the body, one argument per line

  local begin="# >>> $name (managed by the dotfiles installer) >>>"    # the block's opening delimiter
  local end="# <<< $name (managed by the dotfiles installer) <<<"    # and its closing one
  local desired existing temp action=Enabled    # "Enabled" unless an older block turns up

  desired="$(printf '%s\n' "$begin" "$@" "$end")"    # the block as it should read

  if [ -f "$file" ] && grep -Fqx "$begin" "$file"; then    # a block of this name is already present
    existing="$(awk -v begin="$begin" -v end="$end" '
      $0 == begin { inside = 1 }    # start capturing at the opening delimiter
      inside { print }
      $0 == end { inside = 0 }    # stop after printing the closing one
    ' "$file")"

    if [ "$existing" = "$desired" ]; then    # already correct
      return 0    # leave the file untouched
    fi

    temp="$file.dotfiles-tmp.$$"    # $$ keeps concurrent runs off each other's file
    awk -v begin="$begin" -v end="$end" '
      $0 == begin { skipping = 1 }    # swallow the stale block
      !skipping { print }
      $0 == end { skipping = 0 }    # resume printing after it
    ' "$file" > "$temp"
    cat "$temp" > "$file"    # copy back to keep the file's permissions
    rm -f "$temp"
    action=Updated    # say so in the log line below
  fi

  # Separate the block from the surrounding file, without stacking up blank
  # lines each time the block is rewritten.
  if [ -s "$file" ] && [ -n "$(tail -n 1 "$file")" ]; then    # non-empty file whose last line has content
    printf '\n' >> "$file"    # one blank line, and only one
  fi
  printf '%s\n' "$desired" >> "$file"    # the block always goes at the end
  log "$action $name in $file"
}

# Keep Homebrew's executables ahead of the operating-system versions in future
# shells. Homebrew may be available to this installer through an inherited PATH
# even when a fresh login shell would not find it.
BREW_SHELLENV_HANDLED=${BREW_SHELLENV_HANDLED:-0}    # survives being sourced more than once
persist_brew_shellenv() {
  local brew_path profile    # where brew lives, and the start-up file to edit

  # Several components install packages, and the answer cannot change during one
  # run; check the start-up file once instead of once per package list.
  if [ "$BREW_SHELLENV_HANDLED" -eq 1 ]; then    # already done earlier in this run
    return 0
  fi
  BREW_SHELLENV_HANDLED=1    # claim it before doing the work

  brew_path="$(command -v brew)"    # the caller has already checked that brew exists

  case "${SHELL:-}" in    # the login shell decides which file is read
    */zsh) profile="$HOME/.zprofile" ;;    # zsh reads this one for login shells
    */bash)
      case "$(uname -s)" in
        Darwin) profile="$HOME/.bash_profile" ;;    # Terminal.app opens login shells
        *) profile="$HOME/.bashrc" ;;    # elsewhere the interactive file is the reliable one
      esac
      ;;
    *)
      log "Homebrew is installed, but ${SHELL:-the current shell} is not supported for automatic PATH setup."
      return
      ;;
  esac

  # Drop the two-line block an earlier installer appended, then write the same
  # eval as a managed block that later runs can find and rewrite.
  remove_legacy_lines "$profile" \
    '# Homebrew environment (managed by the dotfiles installer)' 2
  write_managed_block "$profile" 'Homebrew environment' \
    "eval \"\$($brew_path shellenv)\""    # the path is fixed now, the eval runs at shell start-up
}

# Component installers take no options; keep their command-line interface strict.
require_no_args() {
  case "${1:-}" in
    '') ;;    # no argument: the normal case
    -h|--help) printf 'Usage: %s\n' "$0"; exit 0 ;;    # the name is all there is to say
    *) printf 'Unknown option: %s\n' "$1" >&2; exit 2 ;;    # refuse rather than ignore it
  esac
}

# Bring each requested Homebrew package to the desired state:
# install it when missing, upgrade it when outdated, or leave it alone when current.
# Pass --cask first for graphical applications and fonts; formulas are the default.
brew_install() {
  if ! has brew; then    # this installer does not bootstrap Homebrew itself
    log 'Homebrew is required. Install it from https://brew.sh and run this installer again.'
    return 1
  fi

  persist_brew_shellenv    # make sure future shells find what is installed below

  local kind_flag=--formula    # formulas unless told otherwise

  if [ "${1:-}" = --cask ]; then    # only ever the first argument
    kind_flag=--cask
    shift    # leave "$@" holding package names alone
  fi

  local package outdated outdated_status    # the name, brew's report, and its exit status
  for package in "$@"; do
    # `brew list` checks the local installation receipt without installing anything.
    if ! brew list "$kind_flag" "$package" >/dev/null 2>&1; then    # not installed at all
      log "Installing $package"
      brew install "$kind_flag" "$package"
      continue    # a fresh install is current by definition
    fi

    # Homebrew exits 1 when a specifically named package is outdated, so preserve
    # both its output and status instead of treating every non-zero status as an error.
    outdated=''
    if outdated="$(brew outdated --quiet "$kind_flag" "$package")"; then    # status 0: nothing to do
      outdated_status=0
    else
      outdated_status=$?    # read it before the next command overwrites it
    fi

    if [ "$outdated_status" -gt 1 ] || { [ "$outdated_status" -eq 1 ] && [ -z "$outdated" ]; }; then    # a real failure, not an outdated package
      log "Could not check whether $package is outdated."
      return 1
    fi

    if [ -n "$outdated" ]; then    # brew named the package, so it is behind
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
  local app=$1 cask=$2    # the bundle name in /Applications, and the cask that installs it

  if [ -d "/Applications/$app.app" ] && ! brew list --cask "$cask" >/dev/null 2>&1; then    # present, but not Homebrew's doing
    log "$app is already installed outside Homebrew; leaving it in place"
    return 0
  fi

  brew_install --cask "$cask"    # install it, or upgrade the copy Homebrew owns
}

# Report a copy of a command that this installer cannot keep current: a program
# installed by hand, or by another package manager, still wins the PATH lookup
# and goes on running its own older version after Homebrew upgrades ours.
warn_if_shadowed() {
  local command_name=$1 active brew_prefix brew_copy    # the command, the copy PATH finds, and Homebrew's

  has brew || return 0    # without Homebrew there is nothing to compare against
  has "$command_name" || return 0    # nor with a command that is not installed

  brew_prefix="$(brew --prefix 2>/dev/null)" || return 0    # say nothing rather than guess
  if [ -z "$brew_prefix" ]; then
    return 0
  fi

  brew_copy="$brew_prefix/bin/$command_name"    # where Homebrew would have put it
  if [ ! -x "$brew_copy" ]; then    # Homebrew never installed this command
    return 0
  fi

  active="$(command -v "$command_name")"    # the copy a shell would actually run
  if [ "$active" = "$brew_copy" ]; then    # the right one already wins
    return 0
  fi

  log "$command_name runs from $active, which this installer does not update."
  log "Homebrew's copy is $brew_copy; put $brew_prefix/bin earlier on PATH to use it."
}

# Point a standard config location at a file or directory in this repository.
# Preserve a user's real file/directory as a timestamped backup before replacing it.
link_config() {
  local source=$1 target=$2    # the tracked file, and the path the tool reads
  mkdir -p "$(dirname "$target")"    # the tool may not have created its directory yet

  # An exact existing link needs no work and, importantly, no new backup.
  if [ -L "$target" ] && [ "$(readlink "$target")" = "$source" ]; then    # already ours, pointing here
    log "Already linked $target"
    return
  fi

  # Back up anything else that is already there, including a link to a different
  # location and a link whose target is missing: both may be the user's own
  # configuration, and replacing them outright would leave no way back.
  if [ -e "$target" ] || [ -L "$target" ]; then    # -L also catches a link that dangles
    local backup="${target}.bak.$(date +%s)"    # seconds since the epoch keep the names unique
    log "Backing up $target to $backup"
    mv "$target" "$backup"
  fi

  log "Linking $target"
  ln -sfn "$source" "$target"    # -n links beside a directory rather than inside it
}
