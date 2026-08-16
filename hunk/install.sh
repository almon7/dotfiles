#!/usr/bin/env bash
# Install the Hunk terminal diff viewer.
set -euo pipefail

LABEL=hunk
source "$(dirname "${BASH_SOURCE[0]}")/../install-lib.sh"
require_no_args "$@"

case "$(uname -s)" in
  Darwin|Linux) brew_install hunk ;;
  *) log 'Only macOS and Linux are supported.'; exit 1 ;;
esac
