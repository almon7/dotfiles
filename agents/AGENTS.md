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
