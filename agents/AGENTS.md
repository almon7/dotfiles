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

## Commits

Commit messages follow [Conventional Commits 1.0.0][cc], whose requirement
words carry their [RFC 2119][rfc2119] force: MUST is absolute, SHOULD may be
set aside only once the consequences are understood, MAY is a free choice.

```
<type>[optional scope][!]: <description>

[optional body]

[optional footer(s)]
```

- The subject MUST open with a type and `: ` — `feat` for a new feature, `fix`
  for a bug fix, or one of `docs`, `test`, `refactor`, `perf`, `style`,
  `build`, `ci`, `chore` for everything else.
- A scope MAY follow the type in parentheses, naming the part of the codebase
  that changed: `fix(parser): reject an unterminated string`.
- A body MAY follow the description after one blank line, and is the place to
  say why the change was needed rather than what the diff already shows.
- Footers MAY follow the body after another blank line, written as
  `Token: value` with hyphens standing in for spaces, e.g. `Refs: #12`.
- A breaking change MUST be flagged, either with `!` before the colon or with a
  `BREAKING CHANGE: <description>` footer. That token stays uppercase; the rest
  of the message is case-insensitive.
- Types and scopes SHOULD be lowercase and the subject SHOULD fit in about 72
  columns, so `git log --oneline` stays readable.

[cc]: https://www.conventionalcommits.org/en/v1.0.0/
[rfc2119]: https://www.rfc-editor.org/rfc/rfc2119.txt
