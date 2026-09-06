#!/usr/bin/env bash
# Install the Context7 CLI, which the find-docs skill runs to fetch library
# documentation. The skill itself is tracked with the other shared skills in
# agents/skills; this component only provides the `ctx7` command it calls.
set -euo pipefail

LABEL=context7
source "$(dirname "${BASH_SOURCE[0]}")/../install-lib.sh"
require_no_args "$@"

# The CLI ships on npm, so this component needs Node whether or not nvim, the
# other component that installs it, was selected. brew_install installs it when
# missing, upgrades it when outdated and leaves it alone otherwise, so asking
# again here costs nothing on a machine that already has it.
brew_install node

# A Node installed outside Homebrew wins the PATH lookup, and `npm install
# --global` would then write into that installation's prefix instead of this one.
warn_if_shadowed node

# Asking for @latest every time makes this the update path as well as the install
# path, the way a rerun upgrades the Homebrew components.
log 'Installing ctx7 at its latest version'
npm install --global ctx7@latest
