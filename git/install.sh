#!/usr/bin/env bash
# Install Git, link the configuration, and optionally enroll the personal SSH key.
set -euo pipefail    # abort on an error, an unset variable, or a failing pipeline stage

LABEL=git    # the tag log() puts in front of every message
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"    # absolute path of this script's directory
source "$DIR/../install-lib.sh"    # pull in log, has, brew_install, link_config, ...
require_no_args "$@"    # reject anything but an empty argument list or --help

case "$(uname -s)" in    # branch on the kernel name
  Darwin|Linux) brew_install git ;;    # install or upgrade the formula
  *) log 'Only macOS and Linux are supported.'; exit 1 ;;    # anything else is unsupported
esac

warn_if_shadowed git    # point out another git earlier on PATH

has git || { log 'Git is not installed; skipping its configuration.'; exit 0; }    # nothing to configure without it

link_config "$DIR/gitconfig" "$HOME/.gitconfig"    # where Git reads the per-user config

if [ -t 0 ] && [ -t 1 ]; then    # a terminal can answer the key-setup prompts
  "$DIR/setup-accounts.sh"    # create or verify the personal GitHub SSH key
elif [ -f "$HOME/.ssh/id_ed25519_personal" ]; then    # unattended, but a key already exists
  "$DIR/setup-accounts.sh"    # so re-verify it without prompting
else
  log 'Skipping SSH-key creation in this unattended run'    # nothing to do without a terminal
fi
