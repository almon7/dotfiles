# Claude Code profiles

This component adds a DeepSeek launcher and a status line showing the active model, reasoning effort, working directory, git branch and used context to an existing Claude Code installation. It does not install Claude Code itself.

Install the configuration with:

```sh
./install.sh claude
```

Use `claude` normally for Anthropic models and `claude-ds` for DeepSeek. `claude-ds` sets DeepSeek's routing variables only for the Claude Code process it starts, so exiting that session is all switching back requires. Arguments are forwarded unchanged, for example `claude-ds --continue`.

## DeepSeek API key

The API key is deliberately outside this repository. Save only the key, with no `export` or quotes, at `~/.config/claude/deepseek-api-key`:

```sh
mkdir -p ~/.config/claude
chmod 700 ~/.config/claude
read -rsp 'DeepSeek API key: ' key; printf '\n'
(umask 077; printf '%s\n' "$key" > ~/.config/claude/deepseek-api-key)
chmod 600 ~/.config/claude/deepseek-api-key
unset key
```

Do not add the DeepSeek variables to `.bashrc` or `.zshrc`: global exports also redirect the ordinary `claude` command. If those exports already exist, remove `ANTHROPIC_BASE_URL`, `ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_MODEL`, the three `ANTHROPIC_DEFAULT_*_MODEL` variables, and the three `CLAUDE_CODE_*` variables from the shell startup file.

## Status line

The status line reads the JSON Claude Code provides and displays the active model, reasoning effort, working directory, git branch and used context, for example:

```text
[Opus 5] · xhigh · ~/dotfiles · main · 37% context
[deepseek-flash[1m]] · max · ~/dotfiles · main · 12% context
```

The effort level is the session's own, so `/effort`, a `modelSettings` entry and `CLAUDE_CODE_EFFORT_LEVEL` all move it, and `claude-ds` pins it to `max`. A model that does not take the effort parameter leaves that segment out. The branch is read with `git branch --show-current` in the reported directory, so it is absent outside a repository, and the directory is shortened to `~` only under your home directory.

The installer adds `statusLine` when `~/.claude/settings.json` does not already contain it. A different existing `statusLine` remains untouched and is reported, matching the repository's local-settings-win policy.

Run the offline regression tests with `python3 claude/test_claude.py`.
