#!/usr/bin/env bash
# Install WezTerm on macOS and link its configuration.
# Stop immediately if an installation or linking step fails.
set -euo pipefail

# Load shared helpers; LABEL prefixes their messages with this component's name.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LABEL=wezterm
source "$DIR/../install-lib.sh"
require_no_args "$@"

# Homebrew's WezTerm cask is macOS-only. Linux still receives the config link below.
case "$(uname -s)" in
  Darwin) brew_install_app WezTerm wezterm ;;
  Linux) log 'The Homebrew WezTerm cask is macOS-only; install WezTerm manually on Linux.' ;;
  *) log 'Only macOS and Linux are supported.'; exit 1 ;;
esac

# WezTerm reads this file directly from the user's home directory.
link_config "$DIR/.wezterm.lua" "$HOME/.wezterm.lua"

install_shell_integration() {
  local integration= candidate rc_file

  for candidate in \
    /Applications/WezTerm.app/Contents/Resources/wezterm.sh \
    /opt/homebrew/share/wezterm/wezterm.sh \
    /usr/local/share/wezterm/wezterm.sh \
    /usr/share/wezterm/wezterm.sh
  do
    if [ -r "$candidate" ]; then
      integration=$candidate
      break
    fi
  done

  if [ -z "$integration" ]; then
    log 'Shell integration script not found; skipping shell setup.'
    return
  fi

  case "${SHELL:-}" in
    */zsh) rc_file="$HOME/.zshrc" ;;
    */bash) rc_file="$HOME/.bashrc" ;;
    *)
      log "Shell integration supports zsh and bash; skipping ${SHELL:-unknown shell}."
      return
      ;;
  esac

  # Earlier versions appended a five-line block under a plain comment; remove it
  # so the managed block below replaces it rather than being added beside it.
  remove_legacy_lines "$rc_file" \
    '# WezTerm shell integration (managed by the dotfiles installer)' 5
  # A managed block is rewritten when WezTerm moves, instead of leaving the old
  # path behind next to the new one.
  write_managed_block "$rc_file" 'WezTerm shell integration' \
    '# Neovim terminals can expose tmux-wrapped OSC sequences as visible text.' \
    'if [ -z "${NVIM:-}" ]; then' \
    "  source \"$integration\"" \
    'fi'
}

install_shell_integration
