# Starship prompt

Run `./install.sh starship`, then open a fresh terminal or tmux pane. The installer installs or updates Starship through Homebrew on macOS and Linux, links `starship.toml` to `~/.config/starship.toml`, and adds a managed initialization block for the login shell selected by `$SHELL` (Zsh or Bash). Bash receives the block in `.bashrc` and its first existing login profile; initialization runs once per interactive shell.

Bash also links `init.bash` to `~/.config/starship/init.bash`. Its prompt hook preserves WezTerm's input-boundary markers after Starship renders the prompt. The existing WezTerm integration remains disabled in Neovim terminals.

The two-line prompt keeps command input on its own line:

```text
~/projects/my-app/src main [!?] 3s
❯
```

- The directory is the full path from `~`, including every directory above and below a Git repository. Paths outside home stay absolute.
- The Git branch appears inside repositories. The bracketed Git indicators mean `!` modified, `+` staged, `?` untracked, `~` renamed, `x` deleted, `=` conflicted, and `$` stashed. `⇡`, `⇣`, and `⇕` indicate ahead, behind, and diverged relative to the locally known upstream; displaying the prompt never fetches updates.
- SSH sessions show `user@host`. Starship also shows the username locally for root or a user different from the login user.
- Command duration appears after commands taking at least two seconds. The `❯` is green after success and red after failure.
- A blank line separates prompts. Language versions, clocks, and cloud information are omitted. No additional font is needed for the prompt symbols.

Edit [`starship.toml`](starship.toml) to customize the prompt; the next prompt reads the new configuration. See the [Starship configuration reference](https://starship.rs/config/) for module options. Existing files at the configuration link are backed up using the installer's usual `.bak.<epoch>` convention. Shell initialization is guarded so removing the Starship executable does not prevent opening a shell.

## Regression checks

Run `python3 starship/test_starship.py` from the repository root. The installer checks use a temporary home and mocked Homebrew. When Starship is installed, the suite also opens isolated Bash terminals to check command timing, failure colors, and WezTerm prompt markers in both initialization orders when WezTerm's integration script is available. The suite does not change the live shell configuration.
