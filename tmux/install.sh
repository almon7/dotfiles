#!/usr/bin/env bash
# Install tmux and link its configuration.
# Stop immediately if an installation, clone, or linking step fails.
set -euo pipefail    # abort on an error, an unset variable, or a failing pipeline stage

# Load shared helpers; LABEL prefixes their messages with this component's name.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"    # absolute path of this script's directory
LABEL=tmux    # the tag log() puts in front of every message
source "$DIR/../install-lib.sh"    # pull in log, has, brew_install, link_config, ...
require_no_args "$@"    # reject anything but an empty argument list or --help

# Install tmux itself from Homebrew on either supported platform.
case "$(uname -s)" in    # branch on the kernel name
  Darwin|Linux) brew_install tmux python ;;    # install or upgrade the formula
  *) log 'Only macOS and Linux are supported.'; exit 1 ;;    # anything else is unsupported
esac

warn_if_shadowed tmux    # point out another tmux earlier on PATH

# Git is needed for the plugin-manager checkout, even when tmux is installed alone.
has git || brew_install git    # install Git only when it is missing

PLUGIN_DIR="$HOME/.tmux/plugins"    # where tmux looks for plugins
TPM_DIR="$PLUGIN_DIR/tpm"    # the plugin manager's own checkout
# Clone TPM once, then keep the existing checkout current on later runs.
if [ ! -d "$TPM_DIR/.git" ]; then    # no repository there yet
  log 'Installing tmux plugin manager'
  git clone --depth 1 https://github.com/tmux-plugins/tpm "$TPM_DIR"    # shallow clone, no history needed
else
  log 'Updating tmux plugin manager'
  # A local commit or an unreachable network should not fail the whole install.
  git -C "$TPM_DIR" pull --ff-only --quiet ||    # fast-forward only, never merge
    log 'Could not update the plugin manager; keeping the current checkout'    # carry on regardless
fi

# The selection bridge must be available when tmux first reads the config.
link_config "$DIR/selection-state.sh" "$HOME/.tmux/selection-state.sh"

# tmux reads its per-user configuration from ~/.tmux.conf.
link_config "$DIR/tmux.conf" "$HOME/.tmux.conf"    # link the tracked config into place

# A server that is already running read its configuration before the line that
# publishes this path existed, and it keeps that environment until it is killed.
# The plugin scripts below would find no path there and refuse to run, so put it
# in place; a server started later picks the same value up from the file.
if tmux list-sessions >/dev/null 2>&1; then    # true only when a server is already up
  tmux set-environment -g TMUX_PLUGIN_MANAGER_PATH "$PLUGIN_DIR/"    # the trailing slash is what TPM expects
fi

log 'Installing tmux plugins'
"$TPM_DIR/bin/install_plugins"    # clone every plugin listed in tmux.conf

# install_plugins only fetches plugins that are missing, so ask for the updates
# of the plugins that are already checked out as well.
log 'Updating tmux plugins'
"$TPM_DIR/bin/update_plugins" all || log 'Could not update the plugins; keeping the current versions'    # updates are best effort

# Plugins are sourced when the configuration is read, so sessions that were
# already open keep running without them until the configuration is reloaded.
if tmux list-sessions >/dev/null 2>&1; then    # again, only when a server is up
  log 'Reload open tmux sessions with prefix + r to pick up the plugins'    # the user has to do this part
fi
