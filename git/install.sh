#!/usr/bin/env bash
# Install Git, link the configuration, and optionally enroll the personal SSH key.
set -euo pipefail

LABEL=git
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../install-lib.sh"
require_no_args "$@"

case "$(uname -s)" in
  Darwin|Linux) brew_install git ;;
  *) log 'Only macOS and Linux are supported.'; exit 1 ;;
esac

has git || { log 'Git is not installed; skipping its configuration.'; exit 0; }

link_config "$DIR/gitconfig" "$HOME/.gitconfig"

if [ -t 0 ] && [ -t 1 ]; then
  "$DIR/setup-accounts.sh"
elif [ -f "$HOME/.ssh/id_ed25519_personal" ]; then
  "$DIR/setup-accounts.sh"
else
  log 'Skipping SSH-key creation in this unattended run'
fi
