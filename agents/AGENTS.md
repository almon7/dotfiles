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
- Before removing a worktree, tear down its running stack and clean up all resources created specifically for that worktree, including background processes, containers, networks, volumes, and temporary files. Run the project’s teardown commands while the worktree still exists, and verify cleanup succeeded before removing the worktree. Preserve resources shared with other worktrees.

## Communication Style

- I don't have infinite time: be succinct but complete. Don't make me look up information or, as much as possible, code;
- I don't have infinite memory: Don't make me look up information or, as much as possible, code;

### Say what you mean, concretely

Everything you write is read without the context you had while writing it — a commit message, a code comment, a README line, a review finding, a chat reply. Each of these has to stand on its own.

- Name the thing; never point at it. `this`, `these two`, `that one`, `the operator`, `the group`, `the heading`, `the filter` refer to nothing unless the noun is in the same sentence. Write the noun: "`link_config` and `brew_install`", not "these two"; "the `--all` path in `install.sh`", not "this one".
- Never coin a term and then use it as if it were defined. "A contiguous group", "a filter over one heading" are not concepts a reader can look up; if a phrase like that is doing real work, define it where it first appears or replace it with the literal thing it describes.
- Prefer the literal identifier over a paraphrase of it: file paths, function names, flags, keys, line numbers. `agents/install.sh --refresh-skills` beats "the refresh command".
- Say who acts and what changes. "The picker leaves `git` unticked" — not "grouping these apart means the operator's app is this one minus a group".
- Before sending anything, reread it as someone who has not seen the code or the conversation. If any noun phrase in it cannot be resolved from the text itself, rewrite that sentence.

A real failure, sent as a standalone message with nothing around it:

> The comment I wrote claimed that grouping these two apart means "the operator's app is this one minus a contiguous group", and the README restated it as "a filter over one heading".

Every noun phrase in it is unanswerable: *these two* what? *The operator* is who — the person running the installer, a shell operator, an operator in some expression? *This one* is which one? *A contiguous group* of what, contiguous in what order? *One heading* in which file, and *a filter* over it doing what? The sentence also hides its subject behind "grouping ... means" and quotes two paraphrases instead of the text they paraphrase, so a reader cannot even go check. Written properly it would name the two functions, the file and heading, and the actual rule — and it would then be shorter than the version that says nothing.

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

