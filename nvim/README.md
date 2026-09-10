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

- **Date line:** in Normal mode, press `Space i d` to insert today's local date on a new line below the cursor, for example `04 Sept 2026, Fri`. Month and weekday names are always English. Restart Neovim after updating, or run `:luafile ~/.config/nvim/lua/config/keymaps.lua` in an existing session.

- **Markdown rendering:** disabled by default. Toggle it with `Space u m` or `:RenderMarkdown toggle`.
- **Markdown diagnostics:** disabled by default. Enable them for the current buffer with `:lua vim.diagnostic.enable(true, { bufnr = 0 })`.
- **System clipboard:** regular `y`/`p` stay inside Neovim. Use `Space y` after selecting with `v` or dragging text with the mouse, `Space Y` for the current line, and `Space p` to paste from the system clipboard locally. Over SSH, clipboard yanks use OSC 52; paste with your terminal's `Cmd-V` (macOS) or `Ctrl-Shift-V` (Linux). `Space p` shows that reminder because the SSH provider is copy-only.
- **Markdown linting** uses `markdownlint-cli2`. The `MD013` (line-length) rule
  is disabled via `.markdownlint-cli2.jsonc`, which `lua/plugins/lint.lua` passes
  to the linter with `--config`. Both files live here, so it works automatically
  — no home-directory config needed. (A `~/.markdownlint*` config would *not*
  work: nvim-lint lints over stdin, so the tool resolves config from the cwd,
  never `$HOME`.)

## Navigation

Drag a vertical window separator left or right, or a horizontal window separator up or down, to resize Neovim splits. Ordinary clicks position the editing cursor; dragging text creates a Neovim selection, double-clicking selects a word, and triple-clicking selects a line. The paired tmux config forwards these gestures to Neovim when mouse support is enabled. After updating tmux's mouse bindings, reload with `C-a r`; existing Neovim sessions receive the change without restarting. Copy a Neovim selection with `Space y`; terminal `Cmd-C` / `Ctrl-Shift-C` copies terminal selections only.

Cmd-Up / Cmd-Down in WezTerm scrolls the current Neovim window up / down one line, directly or through tmux. Normal and Visual mode use native Ctrl-y/e scrolling; Insert mode returns to editing after scrolling. In a terminal buffer, the shortcut enters Terminal-Normal mode to browse output; press `i` to resume terminal input. WezTerm sends Ctrl-F9/F10; the mappings also accept the F33/F34 names decoded through tmux.

Ctrl-d/u and Cmd-D/U in WezTerm scroll down/up by one third of the current window height and center the cursor in Normal mode. The distance adapts to resized windows; a numeric prefix overrides the distance in lines (for example, `5 Ctrl-d` or `5 Cmd-D` moves down five lines). WezTerm sends Ctrl-F11/F12 for Cmd-U/D; the mappings also accept the F35/F36 names decoded through tmux.

Cmd-h/j/k/l in WezTerm moves left/down/up/right through Neovim splits and adjacent tmux panes, stopping at the outer edges. It works in Normal mode, plain `:terminal` buffers, and Snacks terminals, including the first navigation keypress before the plugin has loaded. Ctrl-h/j/k/l no longer triggers split or pane navigation; native editing and picker bindings receive those keys. Ordinary Insert-mode editing shortcuts are preserved. Ctrl-\ returns to the previous Neovim window or tmux pane from Normal mode.

Snacks pickers treat the search input and results as one panel: Cmd-h/l moves between panels (and the editor beside the explorer), then into tmux when there is no panel in that direction. Cmd-j/k moves directly to tmux panes below/above; j/k in Normal mode and Ctrl-n/p move through results. Outside tmux, movement stops when there is no eligible Neovim window.

WezTerm sends Ctrl-F1/F2/F3/F4 for Cmd-h/j/k/l, and Neovim maps those terminal keys to navigation. Neovim also accepts the F25/F26/F27/F28 names produced by tmux’s terminfo encoding. Other terminal emulators must send the same keys. Cmd-n/p changes tmux windows; Cmd-]/[ changes tmux sessions.

The paired [tmux bindings](../tmux/README.md#keys) work locally and when SSH connects directly to remote tmux/Neovim. Existing Neovim sessions retain their loaded Lua configuration; open a fresh session after updating these mappings.

## Updating

The config is symlinked, so editing `~/.config/nvim` edits the repo. Commit and
push, then `git pull` on your other machines:

```sh
cd ~/dotfiles && git add -A && git commit -m "nvim: ..." && git push
```
