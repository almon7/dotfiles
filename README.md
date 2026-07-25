# dotfiles

My personal dev-environment config, and an installer that reproduces it in a
GitHub Codespace (or any Debian/Ubuntu box).

## Contents

| Path | What it is |
|---|---|
| [`nvim/`](nvim/README.md) | Neovim config (LazyVim). See its README for manual, per-OS setup. |
| [`install.sh`](install.sh) | One-shot environment installer (Codespaces / Debian / Ubuntu). |
| `vscode_coding_profile.code-profile` | Exported VS Code profile. |

## Install

### GitHub Codespaces (automatic)

`install.sh` sets up the whole environment: recent **Neovim** + the config,
the tools it needs (**ripgrep**, **fd**, a C compiler), **lazygit**, the
**Claude Code** CLI, `git` editor → `nvim`, and `EDITOR=nvim`.

To run it automatically when you **create** a codespace:

1. Go to **[github.com/settings/codespaces](https://github.com/settings/codespaces)**
   → **Dotfiles** → tick **"Automatically install dotfiles"** (it uses this repo).
2. **Create a new codespace.** (Toggling the setting does *not* affect existing
   codespaces, and rebuilding one does *not* pick dotfiles up — see below.)

**Persistence — important:** personal dotfiles run **only when a codespace is
first created**, *not* on rebuild and *not* on stop/start.

- **Stop → Start** keeps the whole container, so nvim and everything else stay put.
- **Rebuild** re-runs the devcontainer (image + features + `postCreateCommand`)
  but **not** your dotfiles — a rebuilt codespace loses dotfiles-installed tools.
- To make the setup survive **rebuilds** too, run the installer from the project's
  devcontainer — `postCreateCommand` runs on create *and* rebuild:
  ```json
  {
    "postCreateCommand": "git clone https://github.com/almon7/dotfiles ~/dotfiles 2>/dev/null; bash ~/dotfiles/install.sh"
  }
  ```
  Only do this in repos that are **yours** — it installs your setup for anyone
  who opens them.

> **Fonts are client-side.** In a codespace the terminal font is rendered by your
> local VS Code / browser, so set a [Nerd Font](https://www.nerdfonts.com) in
> VS Code's `terminal.integrated.fontFamily` — installing one in the container
> does nothing.

### Local machine

Clone the repo, then follow the editor setup in
[`nvim/README.md`](nvim/README.md):

```sh
git clone git@github.com:almon7/dotfiles.git ~/dotfiles
```

On Debian/Ubuntu you can also just run `./install.sh`.

### Claude Code per-project (optional)

Dotfiles install Claude Code for **you** in all your codespaces. If you also want
a specific repo to ship it to **anyone** who opens it (teammates, CI), add the
maintained feature to that repo's `.devcontainer/devcontainer.json`:

```json
{
  "features": {
    "ghcr.io/anthropics/devcontainer-features/claude-code:1": {}
  }
}
```

Having it in both places is harmless — it just installs once from each.
