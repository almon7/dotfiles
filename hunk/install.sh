#!/usr/bin/env bash
# Install the Hunk terminal diff viewer.
# Stop immediately if the installation fails.
set -euo pipefail

# Load shared helpers; LABEL prefixes their messages with this component's name.
LABEL=hunk
source "$(dirname "${BASH_SOURCE[0]}")/../install-lib.sh"
require_no_args "$@"

# Hunk is distributed as a Homebrew formula on both supported platforms.
case "$(uname -s)" in
  Darwin|Linux) brew_install hunk ;;
  *) log 'Only macOS and Linux are supported.'; exit 1 ;;
esac
