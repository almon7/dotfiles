# dotfiles

My personal dev-environment config, and an installer that reproduces it on a Mac
or a Debian/Ubuntu VPS.

## Quick start

### macOS or Linux

Install [Homebrew](https://brew.sh) — the package manager everything here comes
from — then:

```sh
git clone https://github.com/almon7/dotfiles.git ~/dotfiles
~/dotfiles/install.sh
```

On macOS the installer adds two things Linux does not need:

- **The Xcode Command Line Tools**, because Neovim's Treesitter compiles its
  syntax parsers from C source and needs a compiler to do it.
- **A Nerd Font** (JetBrainsMono) — an ordinary font with icon glyphs patched
  in, which is what draws the file-type icons and status-line symbols in the
  editor. Set it as your terminal font afterwards or you get tofu boxes.

### A fresh Debian/Ubuntu VPS

A new server accepts password logins from the entire internet, so harden it
before you put any work on it. That means four things, and
[`docs/vps.md`](docs/vps.md) walks through each:

- Log in with an **SSH key** instead of a password.
- **Turn password authentication off**, so a guessed password is no longer a
  way in.
- **Close every port but SSH** with a firewall; anything you run on the box is
  reached through an SSH tunnel rather than published.
- **Add swap**, so a memory spike suspends work instead of killing the box.

Then:

```sh
sudo apt-get update
sudo apt-get install -y build-essential procps curl file git
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
git clone https://github.com/almon7/dotfiles ~/dotfiles
bash ~/dotfiles/install.sh
```

- The `apt-get` packages are Homebrew's own prerequisites on Linux. They are
  the only things that come from apt — every tool this repo installs comes from
  Homebrew.
- The `curl` line installs Homebrew itself.
- `brew shellenv` prints the environment variables that put `brew` and its
  packages on `PATH`. The `eval` applies them to this shell only; the dotfiles
  installer then writes the same line into your shell profile, so later logins
  get it without being asked.

### Choosing what to install

- `./install.sh` opens an interactive checklist (`↑`/`↓` or `j`/`k` to move,
  Space to toggle, Enter to install).
- `./install.sh --all` skips the prompt.
- Components can be installed individually: `./install.sh nvim tmux`.
- Every component folder also holds a standalone installer, so
  `./nvim/install.sh` works on its own.
- With no terminal to ask — a pipe, or CI — everything is installed.

Afterwards, set the Nerd Font as your terminal font, and see
[`git/README.md`](git/README.md) to enroll an SSH key with GitHub and
[`nvim/README.md`](nvim/README.md) for the editor's first launch.

## What's in it

Each name below is a component: a folder with its own installer, and an
argument you can pass to `install.sh`. Everything is installed through Homebrew
on both macOS and Linux wherever a formula exists.

- **`agents`** — the standing instructions and the skills folder both coding
  agents read. Claude Code and Codex each hard-code their own paths, so one
  tracked file and one tracked folder are linked to both.
  [One instructions file for every agent](agents/README.md#one-set-of-instructions-for-every-agent),
  [one skills folder for every agent](agents/README.md#one-set-of-skills-for-every-agent)
- **`codex`** — a check, not an install. It reads Codex's own
  `~/.codex/config.toml`, adds any setting from
  [`codex/config.toml`](codex/config.toml) that is missing, and reports a key
  that is already set to something else without touching it.
  [Codex settings](agents/README.md#codex-settings)
- **`context7`** — the `ctx7` CLI that the `find-docs` skill calls to fetch
  current library documentation, plus Node to run it. The one component
  installed from npm rather than Homebrew, because that is where it ships.
  [The find-docs skill and its two sources](agents/README.md#find-docs-and-the-two-things-it-looks-up)
- **`git`** — Git, a `~/.gitconfig` setting the commit identity and `nvim` as
  the editor, and a GitHub SSH key for this machine.
  [Git identity and GitHub SSH](git/README.md)
- **`hunk`** — a terminal UI for reading diffs, which is mostly how you review
  what an agent just wrote.
- **`lazysql`** — a terminal UI for browsing a database, so a query is one
  keystroke away from the shell rather than a detour through a GUI client.
- **`nvim`** — Neovim and this config, plus what it shells out to: ripgrep and
  fd for the file and grep pickers, Node and a C compiler for plugins and
  Treesitter, Python for the Mason-installed language server, lazygit for
  `<leader>gg`, and a Nerd Font on macOS.
  [Neovim config and first launch](nvim/README.md)
- **`tmux`** — tmux, its config, and its plugins. Work runs inside a tmux
  session so a dropped SSH connection leaves it running server-side instead of
  killing it. [tmux keys, sessions and clipboard](tmux/README.md)
- **`wezterm`** — WezTerm and its config. The Homebrew cask is macOS-only, so
  on Linux install the terminal yourself; the config is linked either way.
  [WezTerm keys, mouse and terminal integration](wezterm/README.md)

Codex itself is not installed by any of them — the `codex` component only
checks the settings of a Codex that is already there, or waiting to be.

## Reruns and updates

Every installer is idempotent — running it twice leaves the machine as running
it once did — so rerunning is also how you update:

- Homebrew packages upgrade when Homebrew reports them as outdated.
- tmux's plugin manager and its plugins are pulled.
- The installer's own blocks in your shell start-up files are rewritten in
  place, so a moved path is corrected rather than appended to below the stale
  copy.
- Config links that are already correct are left alone. Anything else sitting
  at the target — a real file, a link pointing elsewhere — is moved aside to a
  timestamped `.bak` first, so nothing is destroyed.

Two things a rerun deliberately does not touch:

- **A program installed outside Homebrew.** It is not ours to replace, so it is
  left alone; the installer only warns when such a copy wins the `PATH` lookup
  and shadows the one it manages.
- **Neovim plugins**, which stay at the versions pinned in
  `nvim/lazy-lock.json`. Moving them is a deliberate `:Lazy update` followed by
  a commit of the lockfile, so an update is a reviewable change rather than a
  surprise.

The configs are symlinked rather than copied, so the link runs both ways:
editing `~/.config/nvim` or `~/.claude/skills` edits this repository, and shows
up in `git status`.
