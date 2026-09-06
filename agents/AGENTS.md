# Personal agent instructions

## Commits Style

Commit messages follow Conventional Commits 1.0.0, whose requirement
words carry their RFC 2119 force: MUST is absolute, SHOULD may be
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

## Starting work

Before making changes in a repository, bring the checkout up to date, so the
work is built on what is actually on the branch rather than on a stale copy.

- Check the state first with `git status`, and note the current branch and
  whether the tree is clean.
- Fast-forward the branch with `git pull --ff-only`. It refuses rather than
  creating a merge or rewriting local commits, which makes the divergence
  visible instead of silently resolving it.
- If the pull is refused, or the tree is dirty, stop and say so rather than
  reaching for `--rebase`, `--force`, `stash`, or `reset` — deciding what
  happens to diverged or uncommitted work is the user's call.
- If there is no upstream or no network, say that and carry on with the local
  state;
