# Personal agent instructions

## Starting work

Before making changes in a repository, bring the checkout up to date:

- Check the state first with `git status`
- Fast-forward the branch with `git pull --ff-only`
- If the pull is refused, stop and say so rather than reaching for `--rebase`, `--force`, `stash`, or `reset`: deciding what happens to diverged branches is the user's call.
- If there is no upstream or no network, say that and carry on with the local state

## Understand the request

Before answering or acting:

- Identify the user's intended outcome, constraints, and what success means.
- Enrich your understanding using relevant conversation context and available project information and resources. Preserve the user's scope; do not invent requirements.
- Check assumptions and flag mistaken premises that would affect the result.
- Resolve gaps from available context first. Ask a focused question only when the missing information would materially change the answer or action; otherwise proceed with a reasonable assumption, stating it when relevant.
- Keep this step lightweight for simple requests. Share only the interpretation or assumptions the user needs to assess the result.

## Plan, implement, and verify

- Prefer a brief planning phase before implementation; keep trivial changes lightweight.
- Use skills when explicitly requested, needed to handle a specific tool, or useful for a concrete task need. Use `find-docs` when missing documentation or a relevant skill would help complete the task. Check MCP capabilities only when the task needs an integration. Do not make general skill discovery a routine prerequisite, including for requests to commit existing changes.
- After code changes settle and before committing, run `ce-simplify-code`, then `ce-code-review`; address findings and run relevant checks.

## Communication Style

- I don't have infinite time: be succinct but complete. Don't make me look up information or, as much as possible, code;
- I don't have infinite memory: Don't make me look up information or, as much as possible, code;

## Formatting Guide

- Do not hard-wrap prose to a fixed column width. Keep each paragraph and list item on a single source line and let the editor or viewer wrap it visually. Preserve line breaks required by syntax or structure, such as code blocks and nested lists.

## Commits Style

Commit messages follow Conventional Commits 1.0.0, whose requirement words carry their RFC 2119 force: MUST is absolute, SHOULD may be set aside only once the consequences are understood, MAY is a free choice.

```
<type>[optional scope][!]: <description>

[optional body]

[optional footer(s)]
```

- The subject MUST open with a type and `: ` — `feat` for a new feature, `fix` for a bug fix, or one of `docs`, `test`, `refactor`, `perf`, `style`, `build`, `ci`, `chore` for everything else.
- A scope MAY follow the type in parentheses, naming the part of the codebase that changed: `fix(parser): reject an unterminated string`.
- A body MAY follow the description after one blank line, and is the place to say why the change was needed rather than what the diff already shows.
- Footers MAY follow the body after another blank line, written as `Token: value` with hyphens standing in for spaces, e.g. `Refs: #12`.
- A breaking change MUST be flagged, either with `!` before the colon or with a `BREAKING CHANGE: <description>` footer. That token stays uppercase; the rest of the message is case-insensitive.
- Types and scopes SHOULD be lowercase and the subject SHOULD fit in about 72 columns, so `git log --oneline` stays readable.

