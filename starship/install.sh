#!/usr/bin/env bash
# Install the shared Zsh and Bash prompt.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LABEL=starship
source "$DIR/../install-lib.sh"
require_no_args "$@"

case "$(uname -s)" in
  Darwin|Linux) brew_install starship ;;
  *) log 'Only macOS and Linux are supported.'; exit 1 ;;
esac

warn_if_shadowed starship
link_config "$DIR/starship.toml" "$HOME/.config/starship.toml"

case "${SHELL:-}" in
  */zsh)
    shell_guard='[ -n "${ZSH_VERSION:-}" ]'
    init_command='eval "$(starship init zsh)"'
    prompt_hook=prompt_starship_precmd
    rc_files=("$HOME/.zshrc")
    ;;
  */bash)
    shell_guard='[ -n "${BASH_VERSION:-}" ]'
    link_config "$DIR/init.bash" "$HOME/.config/starship/init.bash"
    init_command='source "$HOME/.config/starship/init.bash"'
    prompt_hook=starship_precmd
    rc_files=("$HOME/.bashrc")
    # Login Bash reads the first existing profile instead of .bashrc.
    profile="$HOME/.profile"
    for candidate in "$HOME/.bash_profile" "$HOME/.bash_login" "$HOME/.profile"; do
      if [ -f "$candidate" ]; then
        profile=$candidate
        break
      fi
    done
    rc_files+=("$profile")
    ;;
  *) log "Shell initialization supports zsh and bash; skipping ${SHELL:-unknown shell}."; exit 0 ;;
esac

for rc_file in "${rc_files[@]}"; do
  # The function check also avoids initializing twice when a Bash profile sources .bashrc.
  write_managed_block "$rc_file" 'Starship prompt' \
    "if $shell_guard && [ \"\${-#*i}\" != \"\$-\" ] && command -v starship >/dev/null 2>&1 && ! typeset -f $prompt_hook >/dev/null 2>&1; then" \
    "  $init_command" \
    'fi'
done

log 'Open a fresh shell to use the Starship prompt.'
