#!/usr/bin/env bash
# Install WezTerm on macOS and link its configuration.
# Stop immediately if an installation or linking step fails.
set -euo pipefail    # abort on an error, an unset variable, or a failing pipeline stage

# Load shared helpers; LABEL prefixes their messages with this component's name.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"    # absolute path of this script's directory
LABEL=wezterm    # the tag log() puts in front of every message
source "$DIR/../install-lib.sh"    # pull in log, brew_install_app, link_config, ...
require_no_args "$@"    # reject anything but an empty argument list or --help

# Homebrew's WezTerm cask is macOS-only. Linux still receives the config link below.
case "$(uname -s)" in    # branch on the kernel name
  Darwin) brew_install_app WezTerm wezterm ;;    # install the cask unless a manual copy is there
  Linux) log 'The Homebrew WezTerm cask is macOS-only; install WezTerm manually on Linux.' ;;    # config still gets linked
  *) log 'Only macOS and Linux are supported.'; exit 1 ;;    # anything else is unsupported
esac

# WezTerm reads this file directly from the user's home directory.
link_config "$DIR/.wezterm.lua" "$HOME/.wezterm.lua"    # link the tracked config into place

install_shell_integration() {
  local integration= candidate rc_file    # integration starts empty so the search below can detect a miss

  # The places WezTerm ships its shell integration, most specific first.
  for candidate in \
    /Applications/WezTerm.app/Contents/Resources/wezterm.sh \
    /opt/homebrew/share/wezterm/wezterm.sh \
    /usr/local/share/wezterm/wezterm.sh \
    /usr/share/wezterm/wezterm.sh
  do
    if [ -r "$candidate" ]; then    # the first readable one wins
      integration=$candidate
      break
    fi
  done

  if [ -z "$integration" ]; then    # nothing found in any of those places
    log 'Shell integration script not found; skipping shell setup.'
    return
  fi

  case "${SHELL:-}" in    # pick the start-up file the login shell actually reads
    */zsh) rc_file="$HOME/.zshrc" ;;
    */bash) rc_file="$HOME/.bashrc" ;;
    *)
      log "Shell integration supports zsh and bash; skipping ${SHELL:-unknown shell}."
      return
      ;;
  esac

  # Earlier versions appended a five-line block under a plain comment; remove it
  # so the managed block below replaces it rather than being added beside it.
  # The arguments are the file, the marker line, and how many lines to drop.
  remove_legacy_lines "$rc_file" \
    '# WezTerm shell integration (managed by the dotfiles installer)' 5
  # A managed block is rewritten when WezTerm moves, instead of leaving the old
  # path behind next to the new one. Everything after the block's name is one of
  # its lines; the integration path is expanded now, while it is known.
  write_managed_block "$rc_file" 'WezTerm shell integration' \
    '# Neovim terminals can expose tmux-wrapped OSC sequences as visible text.' \
    'if [ -z "${NVIM:-}" ]; then' \
    "  source \"$integration\"" \
    'fi'
}

install_shell_integration    # everything above is only a definition; run it
