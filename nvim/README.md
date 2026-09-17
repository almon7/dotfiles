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
(for `<leader>gg`), **GitHub CLI** (`gh`, for PR reviews), and a
[**Nerd Font**](https://www.nerdfonts.com) (for icons — set it as your terminal
font afterwards).

### Windows (winget, PowerShell)

```powershell
winget install Neovim.Neovim Git.Git OpenJS.NodeJS BurntSushi.ripgrep.MSVC sharkdp.fd
winget install GitHub.cli
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

- **Bottom status bar:** shows Neovim's working directory, shortened with `~`, and that directory's Git branch: `~/work/api  ·  feature/login *  ↑2 ↓1`. The directory follows `:cd`, `:tcd`, `:lcd` and window switches, rather than the active file's repository. `*` means staged, unstaged or untracked changes anywhere in the repository; ignored files do not count. `↑` and `↓` show nonzero commit counts ahead of or behind the configured upstream, using the last fetched state without fetching automatically. Detached HEAD shows a short commit hash. Outside Git, or if Git fails, only the directory appears. Git updates run asynchronously, at most once every two seconds while staying in a directory. Restart Neovim to load the bar. Run its offline checks with `nvim --headless -u NONE -i NONE -l nvim/test_statusline.lua`.

- **Date line:** in Normal mode, press `Space i d` to insert today's local date on a new line below the cursor, for example `04 Sept 2026, Fri`. Month and weekday names are always English. Restart Neovim after updating, or run `:luafile ~/.config/nvim/lua/config/keymaps.lua` in an existing session.

- **Markdown rendering:** disabled by default. Toggle it with `Space u m` or `:RenderMarkdown toggle`.
- **Markdown diagnostics:** disabled by default. Enable them for the current buffer with `:lua vim.diagnostic.enable(true, { bufnr = 0 })`.
- **System clipboard:** regular `y`/`p` stay inside Neovim. Use `Space y` after selecting with `v` or dragging text with the mouse, `Space Y` for the current line, and `Space p` to paste from the system clipboard locally. Over SSH, clipboard yanks use OSC 52; paste with your terminal's `Cmd-V` (macOS) or `Ctrl-Shift-V` (Linux). `Space p` shows that reminder because the SSH provider is copy-only.
- **Copy file location:** in Normal mode, `Space f y` copies a reference such as `dotfiles/agents/AGENTS.md:42:7` to the system clipboard. Paths start with the repository or worktree folder name (`pr-42/src/example.lua` in a worktree named `pr-42`); files outside Git use absolute paths. Config aliases such as `~/.config/nvim` resolve to the repository when needed. Line and byte-column numbers start at 1 and refer to the displayed buffer, including unsaved edits. The shortcut copies no source text and does not save the file. Unnamed buffers, terminals, and file panels leave the clipboard unchanged. Restart Neovim to load the mapping. Run its offline checks with `nvim --headless -u NONE -i NONE -l nvim/test_file_location.lua`.
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

## Git and PR reviews

[Diffview.nvim](https://github.com/sindrets/diffview.nvim) provides side-by-side diffs and file history. In Normal mode, press `Space g v` to see the Diffview menu in Which-key:

| Shortcut | Action |
| --- | --- |
| `Space g v d` | Browse uncommitted changes |
| `Space g v s` | Browse staged changes |
| `Space g v r` | Review the current branch against a prompted base |
| `Space g v f` | Show the current file's history |
| `Space g v h` | Show repository history |
| `Space g v q` | Close the current Diffview |
| `Space g v p` | Pick a GitHub PR to view its published diff |
| `Space g v w` | Pick a PR to open its worktree and diff in a new tmux window |

Inside Diffview, `Tab` / `Shift-Tab` opens the next / previous changed file, `gf` opens the actual file in a normal editing tab, `Space e` focuses the file panel, and `g?` shows the available keys. Existing Git shortcuts, including `Space g g` for LazyGit, remain available.

`Space f y` copies the active Diffview pane's underlying source path, never its virtual `diffview://` name or Git metadata path. Historical panes append `(git commit <full SHA>)`; staged panes append `(git index)`, or `(git index stage 1: base)`, `(git index stage 2: ours)`, or `(git index stage 3: theirs)` during conflicts. Working-tree panes have no suffix. Coordinates belong to the displayed revision and are not translated to the current file; renamed or deleted historical files keep the historical path. Index references describe the current index, not an immutable snapshot. Empty and binary placeholders and the file panel cannot supply a source location.

The branch shortcut suggests the current branch's PR target when GitHub is available, otherwise `origin`'s default branch when known. Enter another ref for stacked PRs or a different base. Selecting a remote branch fetches that branch before comparing its merge base with the current working files, including uncommitted edits.

Authenticate GitHub CLI once with `gh auth login`. Both PR shortcuts load the repository's 50 newest open PRs, including drafts, newest created first. The searchable picker shows each PR's number, title, author, and draft status; type to filter the loaded list and press Enter to select a PR. Choose `Enter PR number or URL…` to enter a number, `#123`, or a full PR URL, or submit an empty manual prompt for the current branch's PR. Press Escape to cancel. If there are no open PRs, the picker still offers manual entry. The PR repository must match a configured HTTPS or SSH remote in the current checkout. PRs from forks work through the base repository's pull-request refs. Listing and fetches run asynchronously and use the PR's actual target branch, including targets other than `main`.

`Space g v p` compares fetched commits without switching branches or including local edits. Its `gf` action opens the current checkout's file, which can differ from the published PR; use `Space g v w` when you need to navigate or run the PR's code. Fetched refs are retained under `refs/diffview/` so open comparisons remain available locally.

`Space g v w` requires Neovim to be running inside tmux. It creates `~/reviews/<host>/<owner>/<repo>/pr-<number>` on the local branch `review/pr-<number>`, then opens a new tmux window named `<repo>/pr-<number>` with Neovim rooted in that worktree and the PR's merge base compared against the working files. An existing matching worktree is reused; updates require a clean worktree and fast-forwardable history. Local edits, local commits, and unrelated directories are never replaced. Worktrees are retained after closing Neovim. Before removing a review worktree, stop its processes and clean up its dedicated resources, then use `git worktree remove <path>` from the repository.

Branch reviews (`Space g v r`) and PR worktree reviews (`Space g v w`) use real files on the right side of the diff, so `gd`, references, and other language-server features work there when the project's language server is configured. The left side remains a historical snapshot. Edits to the working files appear in the diff. Quick PR reviews (`Space g v p`) keep both sides pinned to Git commits; use the worktree shortcut for language-server navigation through the PR's code.

Blank PR prompts also work from the generated review branches. Removing a worktree retains its review branch; reopening the PR reuses that branch only when it still belongs to the same PR and has no conflicting local commits.

Restart Neovim after installing this configuration. The installer includes `gh`; Diffview is installed through lazy.nvim and pinned in `lazy-lock.json`. Run the offline Git/PR regression checks with `nvim --headless -u NONE -i NONE -l nvim/test_diffview.lua`.

## Updating

The config is symlinked, so editing `~/.config/nvim` edits the repo. Commit and
push, then `git pull` on your other machines:

```sh
cd ~/dotfiles && git add -A && git commit -m "nvim: ..." && git push
```
