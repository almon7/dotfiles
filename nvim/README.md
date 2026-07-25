# Neovim

My Neovim config, built on [LazyVim](https://www.lazyvim.org/): **Catppuccin**
colorscheme (Tokyonight is also installed — switch live with `<leader>uC`),
**GitHub Copilot** + **Claude Code**, and language support for Python, JSON,
Markdown and TOML.

> On GitHub Codespaces this installs automatically — see the repo
> [README](../README.md#install). The steps below are for setting it up by hand
> on a workstation. They work **from scratch** on **macOS, Linux and Windows**.

## 1. Prerequisites

Every platform needs: **Neovim ≥ 0.11**, **git**, **Node.js**, a **C compiler**
(for Treesitter), **ripgrep** + **fd** (for the file/grep pickers), and a
[**Nerd Font**](https://www.nerdfonts.com) (for icons — set it as your terminal
font afterwards).

### macOS (Homebrew)

```sh
brew install neovim git node ripgrep fd
brew install --cask font-jetbrains-mono-nerd-font   # a Nerd Font
xcode-select --install                              # C compiler (clang), if not already installed
```

### Linux

Debian / Ubuntu:

```sh
sudo apt update
sudo apt install -y git nodejs npm ripgrep fd-find build-essential
# apt's neovim is usually too old — install a current build instead:
sudo snap install nvim --classic
# (or grab the release tarball from https://github.com/neovim/neovim/releases)
```

Arch:

```sh
sudo pacman -S neovim git nodejs npm ripgrep fd base-devel
```

Fedora:

```sh
sudo dnf install -y neovim git nodejs npm ripgrep fd-find gcc make
```

Then install a [Nerd Font](https://www.nerdfonts.com) and select it in your terminal.

### Windows (winget, PowerShell)

```powershell
winget install Neovim.Neovim Git.Git OpenJS.NodeJS BurntSushi.ripgrep.MSVC sharkdp.fd
winget install zig.zig        # C compiler for Treesitter (or use MinGW / MSVC build tools)
```

Install a [Nerd Font](https://www.nerdfonts.com) and set it in your terminal
([Windows Terminal](https://aka.ms/terminal) recommended).

## 2. Clone the dotfiles repo

macOS / Linux:

```sh
git clone git@github.com:almon7/dotfiles.git ~/dotfiles
# use https://github.com/almon7/dotfiles.git if you haven't set up SSH
```

Windows (PowerShell):

```powershell
git clone https://github.com/almon7/dotfiles.git $env:USERPROFILE\dotfiles
```

## 3. Link the config into place

> If a config already exists, back it up first
> (e.g. `mv ~/.config/nvim ~/.config/nvim.bak`).

macOS / Linux:

```sh
ln -s ~/dotfiles/nvim ~/.config/nvim
```

Windows — PowerShell (needs **Developer Mode** on, or run as **Administrator**):

```powershell
New-Item -ItemType SymbolicLink -Path "$env:LOCALAPPDATA\nvim" -Target "$env:USERPROFILE\dotfiles\nvim"
```

Windows — Command Prompt (as **Administrator**):

```bat
mklink /D "%LOCALAPPDATA%\nvim" "%USERPROFILE%\dotfiles\nvim"
```

## 4. First launch

```sh
nvim
```

LazyVim bootstraps itself and installs every plugin at the versions pinned in
`lazy-lock.json`, then Mason installs the LSP servers, linters and formatters
(stylua, shellcheck, shfmt, flake8, pyright, …). Give it a minute on first run.
Run `:checkhealth` to confirm everything is wired up.

## 5. AI tools (optional)

This config enables two AI integrations:

- **GitHub Copilot** — run `:Copilot auth` inside Neovim to sign in.
- **Claude Code** — install the CLI, then use it from Neovim:
  ```sh
  npm install -g @anthropic-ai/claude-code
  # see https://claude.com/claude-code for other install methods
  ```

## 6. tree-sitter CLI (optional)

`package.json` pins `tree-sitter-cli`, used to build some grammars from source.
It is gitignored as `node_modules/`, so install it only if you want it:

```sh
cd ~/dotfiles/nvim && npm install
```

## Notes

- **Markdown linting** uses `markdownlint-cli2`. The `MD013` (line-length) rule
  is disabled via `.markdownlint-cli2.jsonc`, which `lua/plugins/lint.lua` passes
  to the linter with `--config`. Both files live here, so it works automatically
  — no home-directory config needed. (A `~/.markdownlint*` config would *not*
  work: nvim-lint lints over stdin, so the tool resolves config from the cwd,
  never `$HOME`.)

## Updating

The config is symlinked, so editing `~/.config/nvim` edits the repo. Commit and
push, then `git pull` on your other machines:

```sh
cd ~/dotfiles && git add -A && git commit -m "nvim: ..." && git push
```
