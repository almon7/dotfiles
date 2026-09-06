# Neovim

My Neovim config, built on [LazyVim](https://www.lazyvim.org/): **Catppuccin**
colorscheme (Tokyonight is also installed — switch live with `<leader>uC`),
**Claude Code**, and language support for Python, JSON, Markdown and TOML.

> On macOS and Linux, `./install.sh nvim` does everything in steps 1–3 — see
> the repo [quick start](../README.md#quick-start). The manual walkthrough below
> exists for **Windows**, which the installer does not cover.

## 1. Prerequisites

Every platform needs: **Neovim ≥ 0.11**, **git**, **Node.js**, a **C compiler**
(for Treesitter), **ripgrep** + **fd** (for the file/grep pickers), **lazygit**
(for `<leader>gg`), and a
[**Nerd Font**](https://www.nerdfonts.com) (for icons — set it as your terminal
font afterwards).

### Windows (winget, PowerShell)

```powershell
winget install Neovim.Neovim Git.Git OpenJS.NodeJS BurntSushi.ripgrep.MSVC sharkdp.fd
winget install zig.zig        # C compiler for Treesitter (or use MinGW / MSVC build tools)
```

Install a [Nerd Font](https://www.nerdfonts.com) and set it in your terminal
([Windows Terminal](https://aka.ms/terminal) recommended).

## 2. Clone the dotfiles repo

Windows (PowerShell):

```powershell
git clone https://github.com/almon7/dotfiles.git $env:USERPROFILE\dotfiles
```

## 3. Link the config into place

> If a config already exists, back it up first
> (e.g. `mv "$env:LOCALAPPDATA\nvim" "$env:LOCALAPPDATA\nvim.bak"`).

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

This config enables one AI integration:

- **Claude Code** — install the CLI, then use it from Neovim:
  ```sh
  brew install --cask claude-code
  ```

## 6. tree-sitter CLI (optional)

Install `tree-sitter-cli`, used to build some grammars from source, only if you
want it:

```sh
brew install tree-sitter-cli
```

## Notes

- **System clipboard:** regular `y`/`p` stay inside Neovim. Use `Space y` after
  selecting with `v`, `Space Y` for the current line, and `Space p` to paste
  from the system clipboard.
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
