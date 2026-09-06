# Agent configuration

Claude Code and Codex both read a Markdown file of standing instructions and a
folder of skills, and each hard-codes its own path for both. This component
points every one of those paths at a single tracked file and a single tracked
folder, so the two agents cannot drift apart.

Install both with `./install.sh agents`. The separate `codex` component is not
an installer at all: it checks the settings of Codex itself, and is described in
[Codex settings](#codex-settings) below.

## One set of instructions for every agent

An instructions file is standing context — the preferences an agent should
apply without being reminded, read at the start of every session.

- **Claude Code reads `~/.claude/CLAUDE.md`, Codex reads `~/.codex/AGENTS.md`,
  and neither reads a plain `~/AGENTS.md`.** So the installer links both of
  those names to the single tracked file, [`AGENTS.md`](AGENTS.md).
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

`~/.agents/AGENTS.md` is worth knowing about but is not enough on its own: it is
a proposed cross-vendor convention, and neither agent installed here reads it
today.

Keep the file general. Each agent reads a project's own `AGENTS.md` or
`CLAUDE.md` *after* this one, so repository-specific rules belong there, where
they can contradict it.

## One set of skills for every agent

A skill is a folder holding a `SKILL.md` — instructions an agent loads only when
something in the conversation calls for them, rather than carrying always.

- **Codex reads `~/.agents/skills`, Claude Code reads `~/.claude/skills`.** The
  installer points both at the single tracked folder, [`skills/`](skills), so a
  skill added there reaches both agents at once. Nothing in it is specific to
  either one.
- **They are tracked here rather than written into `~/.claude` by a vendor's
  setup command.** That way they reproduce on a new machine, and a change to
  one shows up in a diff instead of happening invisibly in a home directory.
- **Skills are preferred over MCP servers.** An MCP server's tool definitions
  sit in the context window of every request whether the subject comes up or
  not; a skill costs one line until something activates it.

## find-docs and the Context7 CLI

[`find-docs`](skills/find-docs/SKILL.md) is the Context7 documentation lookup.
It resolves a library name to a Context7 ID and pulls current, version-pinned
snippets for it — worth having because an agent's training data goes stale on
fast-moving libraries long before anything warns you about it.

- **It calls the `ctx7` command**, which the
  [`context7`](../context7/install.sh) component installs.
- **That component is the one place a package comes from npm** rather than
  Homebrew, because npm is where the CLI ships. It installs Node from Homebrew
  first, so selecting it alone is enough — it does not quietly depend on the
  `nvim` component having run.
- **The skill's examples are edited to call the bare `ctx7`** where upstream
  calls `npx ctx7@latest`. Rerunning `./install.sh context7` is what keeps the
  CLI current, so the skill does not pin a version itself.

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

### Refreshing the vendored skill

`find-docs` is vendored: a copy of an upstream file, kept here so it is
versioned with everything else. Refresh it by copying the current version over
it and committing the diff:

```sh
curl -fsSL https://raw.githubusercontent.com/upstash/context7/master/skills/find-docs/SKILL.md \
  -o agents/skills/find-docs/SKILL.md
```

Read that diff before keeping it. It reverts two local edits — the provenance
comment at the top, and the change from `npx ctx7@latest` to the bare `ctx7` —
so restore both before committing.

## Codex settings

Codex reads its own settings from `~/.codex/config.toml`, a file it writes to
itself: logins, history, whatever a future version decides to record there. A
symlink would hand that file to this repository, so
[`codex/config.toml`](../codex/config.toml) is deliberately **not** linked. It is
a list of the settings this machine is meant to have, and `./install.sh codex`
compares it against the live file a key at a time:

| In `~/.codex/config.toml` | What happens |
|---|---|
| the key holds the same value | nothing, and it says so |
| the key is absent | it is inserted, into the table it belongs to |
| the key holds a different value | it is left alone, and reported |
| the file does not exist | it is created with every key |

- **The value already in Codex's config always wins.** A setting changed there
  was changed on purpose, and undoing it silently would be worse than leaving
  the two out of step.
- **To adopt a local change**, copy it into `codex/config.toml` and commit it.
  **To revert one**, delete the key from `~/.codex/config.toml` and rerun.
- **Placement is the part worth knowing.** TOML has no nesting markers: every
  line after a `[table]` header belongs to that table until the next one. So a
  top-level key such as `model` has to be inserted *above* the first header,
  and a table that is not in the file yet is appended whole.
- **Everything else is printed back untouched** — other tables, comments, an
  `[[array]]` of tables.
- **The component installs nothing.** Codex is not on Homebrew and arrives its
  own way; the settings are worth checking before it lands as much as after, so
  a missing Codex is reported rather than treated as a failure.
