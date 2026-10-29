# AGENTS.md

This file provides guidance to coding agents working with code in this
repository. `CLAUDE.md` beside it is a symlink to this file, so Claude Code
(claude.ai/code) reads the same text under the name it looks for; add another
link for any agent that hard-codes a different one.

## What this repository is

A cold-start dev environment: POSIX-ish bash installers plus the config files
they link into place, so one `git clone` and one `./install.sh` reproduce the
setup on a Mac or a Debian/Ubuntu VPS. There is no build or CI. The scripts *are* the product. The skill updater, the two agent-profile components, the Starship prompt, terminal selection, and Neovim PR review, file-location and status-bar helpers have small regression suites; the remaining installers are checked by reading and running them.

## Verification

After editing shell scripts, run the syntax check from the repository root:

```sh
for script in install.sh install-lib.sh */install.sh; do
  bash -n "$script" || exit
done
```

Use the relevant isolated regression suites documented in the component READMEs below. When changing `install.sh`, exercise the dispatcher, including its no-TTY path, in a disposable copy with stub component installers. With no TTY and no named components, the picker is skipped and every component runs, including `git`.

Run installers against the live machine when installation or updating configuration is part of the requested work. Every installer is idempotent, but a rerun is an update: Homebrew packages may upgrade, existing files may be backed up and replaced with links, and managed shell blocks may be rewritten.

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
insert in one without the other silently mislabels the menu, and with it the
line printed above each component as it runs. Every component starts ticked except
`git`, which the picker makes the operator opt into because it replaces
`~/.gitconfig` rather than installing a tool; `--all` and the no-TTY path
install it like any other.

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
  On macOS with Bash, `persist_brew_shellenv` uses the first existing `.bash_profile`, `.bash_login`, or `.profile`, creating `.bash_profile` only when none exists so existing login settings keep loading.

Never append to an rc file, `ln -s`, or shell out to `brew install` directly
inside a component — the helper is where the backup, idempotence, and upgrade
semantics live.

**Platform support is macOS and Linux, through Homebrew on both.** Each
installer branches on `uname -s` and exits with a message on anything else.
Exceptions to know: the WezTerm cask is macOS-only (Linux still gets the config
link), `context7` installs from npm because the CLI is not in Homebrew, and the
nvim installer additionally triggers `xcode-select --install` for Treesitter.

**Things a rerun deliberately does not update:** a program installed outside
Homebrew (reported by `warn_if_shadowed`), and Neovim plugins, which stay pinned
in `nvim/lazy-lock.json` until a deliberate `:Lazy update` plus a commit of the
lockfile. Vendored agent skills are checked during setup and refreshed only with
`./agents/install.sh --refresh-skills`.

### Agent configuration lives here

`agents/` holds the shared instructions and skills. Its installer configures the Claude Code and Codex paths listed below. `codex/` checks Codex's own settings and links a DeepSeek launcher; it does not install Codex itself.

| Repo path | Linked to |
| --- | --- |
| `agents/AGENTS.md` | `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md` |
| `agents/skills/` | `~/.claude/skills`, `~/.agents/skills` |
| `claude/claude-ds` | `~/.local/bin/claude-ds` |
| `claude/statusline.sh` | `~/.claude/statusline.sh` |
| `codex/codex-ds` | `~/.local/bin/codex-ds` |
| `codex/deepseek.config.toml` | `~/.codex/deepseek.config.toml` |
| `codex/deepseek-models.json` | `~/.codex/deepseek-models.json` |
| `nvim/` | `~/.config/nvim` |
| `git/gitconfig` | `~/.gitconfig` |
| `starship/starship.toml` | `~/.config/starship.toml` |
| `starship/init.bash` | `~/.config/starship/init.bash` (Bash only) |
| `tmux/tmux.conf` | `~/.tmux.conf` |
| `tmux/selection-state.sh` | `~/.tmux/selection-state.sh` |
| `wezterm/.wezterm.lua` | `~/.wezterm.lua` |

Consequences to keep in mind while working here:

- **The links run both ways.** Editing `~/.config/nvim/...` or `~/.claude/skills/...`
  edits this repository, and shows up in `git status`.
- **`agents/AGENTS.md` supplies global instructions to both configured agents.** Keep shared defaults general and project-specific rules in the project's `AGENTS.md`/`CLAUDE.md`. Keep the instructions consistent and state any deliberate exception explicitly.
- **`agents/skills/` is the shared skill folder for both agents.** Keep skills tracked here so installation reproduces them. Before changing discovery or refreshing vendored skills, read [agents/README.md](agents/README.md), including its Context7 provenance and refresh requirements.
- **Existing live settings win.** `codex/config.toml` and `claude/settings.json` are not linked because the applications write their own settings. Their installers add missing settings and report differing live values without replacing them. Every tracked Codex setting is intended to be present; there is no opt-out marker. Read [codex/README.md](codex/README.md) or [claude/README.md](claude/README.md) before changing settings or launcher behaviour.
- **DeepSeek keys stay outside Git and config files.** The launchers read the untracked files `~/.config/codex/deepseek-api-key` and `~/.config/claude/deepseek-api-key`. The component READMEs own profile, model-catalogue and launcher details.
- Prefer skills for reusable procedures and use MCP integrations when a task needs access to an external service.

## Keeping the docs in sync

Read the relevant document before changing the area it covers. Each document owns the detail listed below; update that document when the behaviour changes.

| Read | When changing / owns |
| --- | --- |
| [README.md](README.md) | Quick start and component selection |
| [agents/README.md](agents/README.md) | Shared instruction installation, skill discovery, `find-docs`, vendored refresh and updater tests |
| [codex/README.md](codex/README.md) | Codex settings, DeepSeek launcher, profiles, model catalogue and tests |
| [claude/README.md](claude/README.md) | Claude settings, DeepSeek launcher, status line and tests |
| [git/README.md](git/README.md) | Identity, authentication, SSH-key bootstrap and extra profiles |
| [tmux/README.md](tmux/README.md) | Key bindings, session persistence, mouse, clipboard and selection tests |
| [wezterm/README.md](wezterm/README.md) | Terminal keys, mouse, clipboard, typefaces, hyperlinks and tests |
| [nvim/README.md](nvim/README.md) | Setup, navigation, PR reviews, worktree cleanup, file-location copying, status bar, linting and tests |
| [starship/README.md](starship/README.md) | Prompt layout, shell initialisation, configuration and tests |
| [docs/vps.md](docs/vps.md) | Server setup and operations: sshd hardening, ufw, swap, tunnels and Docker |
| [AGENTS.md](AGENTS.md#architecture) | Shared installer contracts and configuration links |

For terminal keys, mouse or clipboard changes spanning WezTerm, tmux and Neovim, read the affected sections in each component's README. For agent instructions or skills, use the installed `writing-for-agents` skill; its tracked source is [agents/skills/writing-for-agents/SKILL.md](agents/skills/writing-for-agents/SKILL.md).

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
