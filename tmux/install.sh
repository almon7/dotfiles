#!/usr/bin/env bash
# Install tmux and link its configuration.
# Stop immediately if an installation, clone, or linking step fails.
set -euo pipefail

# Load shared helpers; LABEL prefixes their messages with this component's name.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LABEL=tmux
source "$DIR/../install-lib.sh"
require_no_args "$@"

# Install tmux itself from Homebrew on either supported platform.
case "$(uname -s)" in
  Darwin|Linux) brew_install tmux ;;
  *) log 'Only macOS and Linux are supported.'; exit 1 ;;
esac

warn_if_shadowed tmux

# Git is needed for the plugin-manager checkout, even when tmux is installed alone.
has git || brew_install git

PLUGIN_DIR="$HOME/.tmux/plugins"
TPM_DIR="$PLUGIN_DIR/tpm"
# Clone TPM once, then keep the existing checkout current on later runs.
if [ ! -d "$TPM_DIR/.git" ]; then
  log 'Installing tmux plugin manager'
  git clone --depth 1 https://github.com/tmux-plugins/tpm "$TPM_DIR"
else
  log 'Updating tmux plugin manager'
  # A local commit or an unreachable network should not fail the whole install.
  git -C "$TPM_DIR" pull --ff-only --quiet ||
    log 'Could not update the plugin manager; keeping the current checkout'
fi

# tmux reads its per-user configuration from ~/.tmux.conf.
link_config "$DIR/tmux.conf" "$HOME/.tmux.conf"

# A server that is already running read its configuration before the line that
# publishes this path existed, and it keeps that environment until it is killed.
# The plugin scripts below would find no path there and refuse to run, so put it
# in place; a server started later picks the same value up from the file.
if tmux list-sessions >/dev/null 2>&1; then
  tmux set-environment -g TMUX_PLUGIN_MANAGER_PATH "$PLUGIN_DIR/"
fi

log 'Installing tmux plugins'
"$TPM_DIR/bin/install_plugins"

# install_plugins only fetches plugins that are missing, so ask for the updates
# of the plugins that are already checked out as well.
log 'Updating tmux plugins'
"$TPM_DIR/bin/update_plugins" all || log 'Could not update the plugins; keeping the current versions'

# Plugins are sourced when the configuration is read, so sessions that were
# already open keep running without them until the configuration is reloaded.
if tmux list-sessions >/dev/null 2>&1; then
  log 'Reload open tmux sessions with prefix + r to pick up the plugins'
fi
