# Agent configuration

This component links Claude Code and Codex to one tracked file of personal instructions and one tracked skills folder, so changes reach both agents.

Install both with `./install.sh agents`. The separate `codex` component checks
the settings of Codex itself and adds a DeepSeek launcher, described in
[Codex settings](#codex-settings) below.

Before changing `agents/install.sh`, read the [shared installer contracts](../AGENTS.md#architecture).

## One set of instructions for every agent

An instructions file is standing context — the preferences an agent should
apply without being reminded, read at the start of every session.

- **The installer links `~/.claude/CLAUDE.md` and `~/.codex/AGENTS.md` to [`AGENTS.md`](AGENTS.md).** These are the personal instruction paths this repository configures for Claude Code and Codex.
- **Editing it in the repository is what changes both agents**, because a
  symlink is read through: there is only ever one file.
- **Nothing is overwritten.** A real file already sitting at either path is
  moved aside as a timestamped backup first.
- **Neither directory has to exist yet.** The installer creates it, so the
  instructions can be in place before the tool that reads them is.

A third tool that reads its own instructions file is a link away by hand:

```sh
ln -s "$PWD/agents/AGENTS.md" ~/.cursor/AGENTS.md
```

Instruction discovery depends on the tool and its configuration. For example, current Claude Code can also load ancestor `AGENTS.md` files under its documented conditions. Check the [Claude Code discovery rules](https://code.claude.com/docs/en/memory#agents-md) and [Codex discovery rules](https://learn.chatgpt.com/docs/agent-configuration/agents-md) before changing the installed paths.

Keep the shared file general and put repository-specific rules in the project's `AGENTS.md` or `CLAUDE.md`. Keep shared defaults and project rules consistent; state any deliberate exception explicitly.

## One set of skills for every agent

A skill is a folder holding a `SKILL.md`. Initial discovery normally exposes the skill's name and description; the instructions load when the skill is activated. See [Codex skill loading](https://learn.chatgpt.com/docs/build-skills) and [Claude Code skill loading](https://code.claude.com/docs/en/skills#control-who-invokes-a-skill).

- **Codex reads `~/.agents/skills`, Claude Code reads `~/.claude/skills`.** The
  installer points both at the single tracked folder, [`skills/`](skills), so a
  skill added there reaches both agents at once. Skills may include agent-specific discovery metadata alongside the shared instructions.
- **They are tracked here rather than written into `~/.claude` by a vendor's
  setup command.** That way they reproduce on a new machine, and a change to
  one shows up in a diff instead of happening invisibly in a home directory.
- **Prefer skills for reusable procedures; use MCP when a task needs an integration.** Tool-definition loading depends on the host and configuration; [Claude Code supports deferred MCP tool definitions](https://code.claude.com/docs/en/mcp#scale-with-mcp-tool-search).

## Test quality

[`test-quality`](skills/test-quality/SKILL.md) helps select useful tests and review tests for regression value. Ask “Use $test-quality to review the tests in this change” or invoke it while adding coverage. The skill checks requirements, existing coverage and assertion quality, permits no new test when existing checks suffice, and preserves distinct behaviours during cleanup. Worked examples cover migration revisions, mocks, source inspection and redundant tests.

The skill is maintained locally and is outside the vendored-skill refresh. The existing shared links expose it to Codex and Claude Code; start a new session if it is not yet listed.

## Uploading Hunk comments to a GitHub PR

[`hunk-pr-comments`](skills/hunk-pr-comments/SKILL.md) copies your notes from an open Hunk session into one pending GitHub PR review. For example, ask your agent: “Upload my Hunk comments to a pending review on PR #123.” The agent loads Hunk's bundled instructions through `hunk skill path`, checks each comment against the PR diff, uploads your text unchanged, and returns a link. You inspect and submit the review on GitHub yourself.

The skill requires Hunk, an open review session, and an authenticated GitHub CLI (`gh`). It includes only your notes by default and leaves the Hunk session intact. If any comment cannot be matched to the PR, or your account already has a pending review, the agent stops without uploading. Keep Hunk open until the transfer succeeds: Hunk 0.21.1 does not save live notes across restarts.

The existing shared skills links make the skill available to both agents; no Hunk extension or additional installer step is needed. After adding the skill, start a new agent session if the skill is not yet listed.

## Matt Pocock's skills

The 27 skills listed in [Matt Pocock's published manifest at `b0618bc`](https://github.com/mattpocock/skills/blob/b0618bc436ad893b3c5e84e55fba86586d34a404/.claude-plugin/plugin.json) are vendored from [mattpocock/skills](https://github.com/mattpocock/skills). That commit is the initial installation snapshot; the refresh command below follows upstream `main`. Complete skill folders, including reference files, templates and agent metadata, live directly under `skills/`. The upstream [MIT licence](licenses/mattpocock-skills.txt) is retained separately.

The existing shared links expose the skills to both agents. They include `grill-me`, `grill-with-docs`, `tdd`, `diagnosing-bugs`, `to-spec`, `implement`, `teach` and their supporting skills. Installing them does not run their workflows or replace the existing `ce-simplify-code` and `ce-code-review` requirements.

Before using the engineering workflows in a project, ask the agent to use `setup-matt-pocock-skills` in that project. Setup is a separate, interactive step: it chooses the issue tracker and documentation layout, writes project configuration and may create tracker labels. The dotfiles installer does not run setup. Start a new agent session if the installed skills are not yet listed.

## Cursor's code-quality review skill

[`thermo-nuclear-code-quality-review`](skills/thermo-nuclear-code-quality-review/SKILL.md) is vendored unchanged from [Cursor Team Kit at `e5136d8`](https://github.com/cursor/plugins/tree/e5136d82418d2db3165ea1050d17577cd618cc05/cursor-team-kit/skills/thermo-nuclear-code-quality-review). That commit is the initial installation snapshot; the refresh command below follows upstream `main`. The upstream [MIT licence](licenses/cursor-team-kit.txt) is retained separately.

For a strict maintainability review of abstractions, branching complexity and large files, run `/thermo-nuclear-code-quality-review` in Claude Code, or ask Codex to “Use thermo-nuclear-code-quality-review to review my changes”. The existing shared links expose the skill to both agents. Its upstream frontmatter retains `disable-model-invocation: true`, so Claude Code requires [manual invocation](https://code.claude.com/docs/en/skills#control-who-invokes-a-skill). Installing the skill does not run a review or replace the existing `ce-simplify-code` and `ce-code-review` requirements.

## Checking and refreshing vendored skills

`ce-simplify-code` and `ce-code-review` come from [EveryInc/compound-engineering-plugin](https://github.com/EveryInc/compound-engineering-plugin); the 27 Matt Pocock skills come from [mattpocock/skills](https://github.com/mattpocock/skills); `thermo-nuclear-code-quality-review` comes from [cursor/plugins](https://github.com/cursor/plugins). `./install.sh agents` checks all 30 skills against the three repositories' `main` branches after linking them. To run only the check:

```sh
./agents/install.sh --check-updates
```

The check fetches each repository once into a temporary directory and compares all files in its selected skill folders, including references and scripts. It reports `up to date` or a difference and prints the upstream snapshot link. A difference can mean an upstream update or a local edit; this is a content comparison, not a version ordering claim. It never overwrites skills or runs downloaded code. Local skills such as `find-docs` and `trello-learning-queue` are outside this check.

The source-to-destination mapping in `check-skill-updates.sh` is explicit: upstream additions are not installed automatically. Adding another skill requires copying its complete folder, adding its mapping and retaining any required attribution.

The check requires Git, diff, and network access to GitHub. A failed check warns without blocking normal setup; the standalone check stops at the first fetch or comparison failure with exit 2, and exits 0 after a successful comparison, including when differences exist. Each clone and sparse-checkout download aborts if the HTTP transfer stays below one byte per second for 60 seconds; this is a stalled-transfer limit, not a total deadline. The installer accepts at most one option, so a check cannot forward a refresh flag.

To refresh all selected skills using one consistent snapshot per upstream repository:

```sh
./agents/install.sh --refresh-skills
git diff -- agents/skills
```

Refresh requires rsync and refuses if any selected skill folder has staged, unstaged, untracked, or ignored files; unrelated dotfiles changes are allowed. It downloads all repositories and validates every selected source and destination before replacing any folder, including deleting files removed upstream. A fetch or source-validation failure therefore leaves all local skills untouched. Committed local customisations are replaced too. Review and commit the resulting diff; Git retains the previous committed versions. Refresh never commits or pushes, and ordinary setup only checks. Cleanliness is checked before and after downloading and again just before each replacement. Copies use content checksums and are compared again before success is reported. If copying or verification fails, the command exits 2 and reports the partial refresh for inspection.

Avoid editing the skill folders while a refresh is copying: the checks do not
lock editors out. The update check compares content, not executable permission
bits, so permission-only upstream changes are not detected.

Run the offline regression tests with Python 3, Git, Bash, diff, and rsync:

```sh
python3 agents/test_skill_updates.py
```

Tests use disposable repositories and mock the network; installed skills and
personal configuration are untouched.

## find-docs, and the two things it looks up

[`find-docs`](skills/find-docs/SKILL.md) supplies documentation or a published skill when the session lacks a needed reference. Its `SKILL.md` holds the lookup steps, with source-specific detail under [`references/`](skills/find-docs/references), read only when that branch is taken.

Documentation, skill, and MCP discovery stay scoped to tooling used by the project or chosen for the task: a shadcn/ui collapsible section calls for shadcn resources, not a generic search for collapsible-section skills. Broader searches are reserved for exploratory research or tooling comparisons.

- **[Context7](skills/find-docs/references/context7.md) serves documentation.**
  It resolves a library name to a Context7 ID and pulls current, version-pinned
  snippets for it, through the `ctx7` command the
  [`context7`](../context7/install.sh) component installs.
- **That component is the one place a package comes from npm** rather than
  Homebrew, because npm is where the CLI ships. It installs Node from Homebrew
  first, so selecting it alone is enough — it does not quietly depend on the
  `nvim` component having run.
- **[skills.sh](skills/find-docs/references/skills-sh.md) serves skills.** It
  indexes public `SKILL.md` files from GitHub, reached through `npx`, so nothing
  is installed for it. Reading a published skill is the default; installing one
  with `-g` writes into this repository through the links above, where it shows
  up as untracked files to commit by hand.
- **What comes back from skills.sh is untrusted text from a stranger's
  repository**, which the skill says at both levels: summarise it, treat its
  commands as proposals, and let this repository's conventions and the user win
  any contradiction.

### Raising the lookup quota

Lookups work unauthenticated on a free monthly quota. To raise the limit, either
log in once:

```sh
ctx7 login
```

or export `CONTEXT7_API_KEY` from a shell start-up file this repository does not
track, such as `~/.bashrc` or `~/.zshrc`.

- **Either way the credential stays out of Git.** A login stores its token in
  `~/.config/context7/credentials.json`, which is outside this repository.
- **The environment variable is the route that works today.** `ctx7 login` was
  hanging at `Preparing login...` when this was set up, and `ctx7 setup` — the
  command the upstream README gives — sits behind the same login and hangs with
  it. That is the other reason the skill is tracked here instead of being
  installed by it.
- **Neither blocks a lookup.** `ctx7 library` and `ctx7 docs` are on a different
  endpoint and work anonymously.
- **When the quota runs out the skill is told to say so**, rather than quietly
  falling back to whatever the model remembers — which is the failure the skill
  exists to prevent.

### Refreshing the vendored Context7 reference

The Context7 half is vendored: a copy of an upstream file, kept here so it is
versioned with everything else. Upstream ships it as a `SKILL.md`; here it is a
reference behind our own. Refresh it by copying the current version over it and
committing the diff:

```sh
curl -fsSL https://raw.githubusercontent.com/upstash/context7/master/skills/find-docs/SKILL.md \
  -o agents/skills/find-docs/references/context7.md
```

Read that diff before keeping it. It reverts three local edits, all of them
listed in the comment at the top of the file: the comment itself, the change from
`npx ctx7@latest` to the bare `ctx7`, and the removal of its "Workflow" and
"Authentication" sections, which `SKILL.md` and the quota section above now own.
Restore all three before committing.

## Codex settings

Before changing Codex settings or the DeepSeek launcher, read [Codex settings and the DeepSeek launcher](../codex/README.md). The [settings check](../codex/README.md#codex-settings) documents how missing keys are inserted and existing values are preserved.
