# Sourced once from the managed Starship block in an interactive Bash shell.
eval "$(starship init bash)"

# Starship replaces PS1 after WezTerm's precmd hook. Restore prompt boundaries
# after rendering, including when Enter redraws a prompt without a command.
__dotfiles_starship_wezterm_prompt() {
  if [ -z "${WEZTERM_SHELL_SKIP_SEMANTIC_ZONES:-}" ] && typeset -f __wezterm_semantic_precmd >/dev/null 2>&1; then
    if [[ "$PS1" != *'\[\e]133;B\a\]'* ]]; then
      PS1='\[\e]133;P;k=i\a\]'$PS1'\[\e]133;B\a\]'
    fi
  fi
  # Bash's DEBUG trap can mistake this post-render hook for the next command.
  STARSHIP_START_TIME= STARSHIP_PREEXEC_READY=true
}

# A later bash-preexec bootstrap can also consume Starship's ready flag.
# Re-arm before its preserved Starship hook times the first real command.
__dotfiles_starship_rearm_timer() { STARSHIP_PREEXEC_READY=true; }
preexec_functions=(__dotfiles_starship_rearm_timer "${preexec_functions[@]}")

if [[ "$(declare -p PROMPT_COMMAND 2>/dev/null)" == 'declare -a '* ]]; then
  PROMPT_COMMAND+=(__dotfiles_starship_wezterm_prompt)
else
  PROMPT_COMMAND="${PROMPT_COMMAND:+$PROMPT_COMMAND$'\n'}__dotfiles_starship_wezterm_prompt"
fi
