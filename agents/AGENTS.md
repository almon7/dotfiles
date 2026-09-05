# Personal agent instructions

One file, read by every coding agent on this machine: Claude Code loads it as
`~/.claude/CLAUDE.md`, Codex as `~/.codex/AGENTS.md`, and anything listed in
`dotfiles/agents/targets` by its own name. Every one of those is a link to this
file, at `dotfiles/agents/AGENTS.md`.

Keep the contents general. Anything true of only one repository belongs in that
repository's own `AGENTS.md` or `CLAUDE.md`, which each agent reads after this
file and may contradict.

## Environment

- The editor is `nvim`, the terminal WezTerm, and long-running work lives in
  tmux with a `C-a` prefix.
- `rg` and `fd` are installed; reach for them before `grep -r` and `find`.
- `lazygit` and `hunk` are there for reading diffs.

## Working style

- Explain why in comments, not what the line already says.
- Prefer editing an existing file over adding a new one, and leave unrelated
  code alone.
- Say plainly when something is untested, skipped or failing, rather than
  reporting it as done.
