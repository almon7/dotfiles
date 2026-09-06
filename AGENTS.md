# AGENTS.md

This file provides guidance to coding agents working with code in this
repository. `CLAUDE.md` beside it is a symlink to this file, so Claude Code
(claude.ai/code) reads the same text under the name it looks for; add another
link for any agent that hard-codes a different one.

## What this repository is

A cold-start dev environment: POSIX-ish bash installers plus the config files
they link into place, so one `git clone` and one `./install.sh` reproduce the
setup on a Mac or a Debian/Ubuntu VPS. There is no build, no test suite, and no
CI. The scripts *are* the product, so correctness comes from reading them and
running them, not from a runner.

## Commands

```sh
./install.sh                 # interactive checklist (arrow/jk, Space, Enter)
./install.sh --all           # every component, no prompts
./install.sh nvim tmux       # only the named components
./nvim/install.sh            # a single component, standalone; takes no options
bash -n install.sh install-lib.sh */install.sh   # syntax check after editing
```

With no TTY (`./install.sh < /dev/null`, CI) the picker is skipped and
everything installs — that path is worth exercising after touching `install.sh`.

Every installer is idempotent, and a rerun is the update path. Rerun freely
while developing: Homebrew packages upgrade, correct symlinks are left alone,
managed shell blocks are rewritten in place.

`shfmt` and `markdownlint-cli2` are not on `PATH`; they come from Mason inside
Neovim (`~/.local/share/nvim/mason/bin`). Lua style is `nvim/stylua.toml`
(2-space, 120 columns); Markdown uses `nvim/.markdownlint-cli2.jsonc` with
`MD013` off.

## Architecture

**`install.sh` is a dispatcher, nothing more.** It renders the checklist,
validates each name against a hard-coded `case`, then runs
`"$ROOT/$component/install.sh"`. Adding or renaming a component means editing
**four** places in that file — `all_components`, the positionally-parallel
`descriptions` array, the `--help` usage line, and the validation `case` — plus
creating `<component>/install.sh`. The two arrays are matched by index, so an
insert in one without the other silently mislabels the menu.

**`install-lib.sh` holds every behaviour worth being consistent about.** Each
component installer is a thin script that sets `DIR` and `LABEL`, sources it,
rejects arguments (`require_no_args "$@"`, or its own `case` in
`agents/install.sh`), and then composes its helpers:

- `link_config <source> <target>` — the only sanctioned way to place a config.
  An already-correct link is a no-op; anything else at the target (a real file,
  a link elsewhere, a dangling link) is moved to a `.bak.<epoch>` first, and the
  parent directory is created so the link can precede the tool's installation.
- `brew_install [--cask] <pkg>...` / `brew_install_app <App> <cask>` — install,
  upgrade when outdated, else leave alone. `brew_install_app` refuses to fight
  a hand-installed `/Applications/<App>.app`.
- `warn_if_shadowed <cmd>` — reports a non-Homebrew copy that wins the `PATH`
  lookup. Deliberately a warning: a program we did not install is not ours to
  replace.
- `write_managed_block <file> <name> <line>...` — the only sanctioned way to
  touch a user's shell start-up file. It rewrites its delimited block in place
  when the contents change, so a moved Homebrew prefix or WezTerm path updates
  rather than appending a second contradictory copy. `remove_legacy_lines`
  exists to retire earlier unmanaged blocks; add a call to it when you change
  the shape of a block a previous version already wrote to real machines.
- `log` / `has` / `persist_brew_shellenv` (runs once per `install.sh` run).

Never append to an rc file, `ln -s`, or shell out to `brew install` directly
inside a component — the helper is where the backup, idempotence, and upgrade
semantics live.

**Platform support is macOS and Linux, through Homebrew on both.** Each
installer branches on `uname -s` and exits with a message on anything else.
Exceptions to know: the WezTerm cask is macOS-only (Linux still gets the config
link), `context7` installs from npm because the CLI is not in Homebrew, and the
nvim installer additionally triggers `xcode-select --install` for Treesitter.

**Two things a rerun deliberately does not update:** a program installed outside
Homebrew (reported by `warn_if_shadowed`), and Neovim plugins, which stay pinned
in `nvim/lazy-lock.json` until a deliberate `:Lazy update` plus a commit of the
lockfile.

### Agent configuration lives here

`agents/` holds what both agents share — the instructions file and the skills
folder — and its installer links each to the paths Claude Code and Codex
hard-code, since neither reads a plain `~/AGENTS.md`. `codex/` is a different
kind of component: it installs nothing and only checks Codex's own settings.
The links are:

| Repo path | Linked to |
|---|---|
| `agents/AGENTS.md` | `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md` |
| `agents/skills/` | `~/.claude/skills`, `~/.agents/skills` |
| `nvim/` | `~/.config/nvim` |
| `git/gitconfig` | `~/.gitconfig` |
| `tmux/tmux.conf` | `~/.tmux.conf` |
| `wezterm/.wezterm.lua` | `~/.wezterm.lua` |

Consequences to keep in mind while working here:

- **The links run both ways.** Editing `~/.config/nvim/...` or `~/.claude/skills/...`
  edits this repository, and shows up in `git status`.
- **`agents/AGENTS.md` is this machine's global agent instruction file.** A
  change to it changes how every agent behaves in every repository, so keep it
  general — anything true of one project belongs in that project's own
  `AGENTS.md`/`CLAUDE.md`, which each agent reads afterwards and may contradict.
- **`agents/skills/` is the shared skill folder for both agents**, which is why
  it sits beside `AGENTS.md` and is linked by the same installer. Skills are
  tracked here rather than written into `~/.claude` by a vendor's setup command,
  so they reproduce on a new machine and show up in a diff. `find-docs` is one
  skill over two sources: a short `SKILL.md`, since a skill's description is in
  the context window of every request, plus a `references/` file read only when
  that branch is taken. Only the Context7 reference is vendored, from upstream
  `upstash/context7` — keep the provenance comment at the top of
  `references/context7.md` when refreshing it.
- **`codex/config.toml` is not linked**, because Codex writes to its own config
  and a link would hand it this repository. `codex/install.sh` compares the two
  a key at a time instead: it inserts a missing key into the table it belongs to
  (a top-level key above the first `[table]` header, or the whole table appended
  when it is absent), and reports — never rewrites — a key whose value differs,
  since a deliberate local change is not ours to undo. Every key in the file is
  one the machine is meant to have; there is no opt-out marker.
- Skills are preferred over MCP servers for the same reason `find-docs` is: an
  MCP server's tool definitions occupy the context window of every request,
  while a skill costs one line until it activates.

## Keeping the docs in sync

The documentation is split so that each fact has one home. A change belongs in
whichever of these owns it:

| File | Owns |
|---|---|
| `README.md` | the quick start and the component table — the fast path, nothing else |
| `agents/README.md` | shared agent instructions, the shared skills folder, `find-docs` and its two sources (`ctx7`, skills.sh), the Codex settings check |
| `git/README.md` | identity vs authentication, the SSH-key bootstrap, extra profiles |
| `tmux/README.md` | prefix and key bindings, resurrect/continuum, copy and paste |
| `nvim/README.md` | the manual Windows path, first launch, linting and clipboard notes |
| `docs/vps.md` | server setup and operations: sshd hardening, ufw, swap, tunnels, Docker |
| `AGENTS.md` | this file — architecture and contracts, what an agent reads first |

All of them go stale silently, because nothing here fails a build when they do.
Treat the doc as part of the change, in the same commit:

- A new or renamed component: add a row to the `README.md` component table and
  edit the dispatcher's four lists above. Give it a README of its own only when
  it has more to say than that row holds, and link it from the row.
- New helpers in `install-lib.sh`, or a change to what an existing one
  guarantees: update the Architecture section here, since its whole purpose is
  to state contracts that are otherwise only visible by reading every caller.
- Key bindings, install paths, or the symlink table changing: the component's
  own README documents them concretely and will contradict reality otherwise.
- Resist moving detail back into `README.md`. It is short on purpose — a reader
  should be able to clone, run the installer, and stop reading.

If a change makes a statement in any of these wrong, correct the file rather
than leaving the code and the prose to disagree.
