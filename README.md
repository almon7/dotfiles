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

To run it automatically in **every** codespace you open:

1. Go to **[github.com/settings/codespaces](https://github.com/settings/codespaces)**
   → **Dotfiles** → tick **"Automatically install dotfiles"** (it uses this repo).
2. Create or rebuild a codespace.

**Persistence:** a normal **Stop → Start** keeps the whole container, so nothing
reinstalls. A **Rebuild** or a **new** codespace starts clean — that's when
`install.sh` re-runs and restores everything.

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
