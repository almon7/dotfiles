#!/usr/bin/env bash
# Install the LazySQL terminal database client.
# Stop immediately if the installation fails.
set -euo pipefail    # abort on an error, an unset variable, or a failing pipeline stage

# Load shared helpers; LABEL prefixes their messages with this component's name.
LABEL=lazysql    # the tag log() puts in front of every message
source "$(dirname "${BASH_SOURCE[0]}")/../install-lib.sh"    # pull in log, has, brew_install, ...
require_no_args "$@"    # reject anything but an empty argument list or --help

# LazySQL is distributed as a Homebrew formula on both supported platforms.
case "$(uname -s)" in    # branch on the kernel name
  Darwin|Linux) brew_install lazysql ;;    # install or upgrade the formula
  *) log 'Only macOS and Linux are supported.'; exit 1 ;;    # anything else is unsupported
esac

warn_if_shadowed lazysql    # point out another lazysql earlier on PATH
