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
  Darwin)
    # A manually installed WezTerm has the same /Applications destination as the
    # Homebrew cask.  Trying to install the cask over it fails with "already an
    # App", so accept a usable existing application instead of requiring a
    # Homebrew receipt.
    if [ -x /Applications/WezTerm.app/Contents/MacOS/wezterm ] &&
       ! brew list --cask wezterm >/dev/null 2>&1; then
      log 'WezTerm is already installed outside Homebrew; leaving it in place'
    else
      brew_install --cask wezterm
    fi
    ;;
  Linux) log 'The Homebrew WezTerm cask is macOS-only; install WezTerm manually on Linux.' ;;
  *) log 'Only macOS and Linux are supported.'; exit 1 ;;
esac

# WezTerm reads this file directly from the user's home directory.
link_config "$DIR/.wezterm.lua" "$HOME/.wezterm.lua"

install_shell_integration() {
  local integration= candidate rc_file source_line

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

  if [ -f "$rc_file" ] && grep -Fq "$integration" "$rc_file"; then
    log "Shell integration is already enabled in $rc_file"
    return
  fi

  if [ -s "$rc_file" ]; then
    printf '\n' >> "$rc_file"
  fi
  source_line="source \"$integration\""
  printf '%s\n%s\n%s\n%s\n%s\n' \
    '# WezTerm shell integration (managed by the dotfiles installer)' \
    '# Neovim terminals can expose tmux-wrapped OSC sequences as visible text.' \
    'if [ -z "${NVIM:-}" ]; then' \
    "  $source_line" \
    'fi' >> "$rc_file"
  log "Enabled shell integration in $rc_file"
}

install_shell_integration
