# tmux

tmux is a terminal multiplexer: the shells you start run inside a server
process, not inside your SSH connection. Close the laptop or drop the
connection and they keep running — Claude Code carries on while you are on a
train, and you reattach to find it finished.

```sh
tmux new -s dev          # start a session named dev
tmux a -t dev            # come back to it
tmux ls                  # what's running
```

Three words to have straight:

- A **session** is one workspace, and what survives a disconnection.
- A **window** is a tab inside it.
- A **pane** is a split within a window.

## Keys

The prefix is **`C-a`** — a key you press first to tell tmux the next key is for
it rather than for the program in the pane. It is remapped from the default
`C-b`, which is a bad key. Press it, release, then press the command key.

| Key | Does |
| --- | --- |
| `C-a d` | Detach — everything keeps running server-side |
| `C-a c` | New window (a tab) |
| `C-a 1`…`9` | Jump to window N |
| `C-a n` / `C-a p` | Next / previous window |
| `C-a ,` | Rename the current window |
| `C-a w` | Pick a window from a list |
| `C-a &` | Close the current window |
| `C-a \|` / `C-a -` | Split vertically / horizontally |
| `C-a h/j/k/l` | Move between panes, stopping at the outer edges |
| `C-h/j/k/l` | Move between panes **and** Neovim splits, stopping at the outer edges (also in tmux copy mode) |
| Left `Option-j` / `Option-k` | Next / previous session in name order, stopping at either end |
| `C-a a` | Return to the last window |
| `C-a C-a` | Send `C-a` to the program in the pane |
| `C-a H/J/K/L` | Move the current pane by swapping it left/down/up/right |
| `C-a z` | Zoom current pane fullscreen (toggle) |
| `C-a [` | Scrollback / copy mode |
| `v` / `C-v` / `y` in copy mode | Begin selection / toggle rectangle / copy and leave copy mode |
| `C-a r` | Reload this config after editing it |
| `C-a C-s` / `C-a C-r` | Save / restore all tmux sessions |
| `C-a ?` | List every binding |

The mouse works too: click panes, drag borders to resize, scroll with the wheel, and **Ctrl-click** a detected link to open it in the OS browser, including from inside tmux.

Neovim navigation works in Normal mode, plain `:terminal` buffers, Snacks terminals, and pickers. Ordinary editing buffers keep their Insert-mode shortcuts. In pickers, Ctrl-h/l moves between panels; Ctrl-j/k moves to tmux panes above/below, while j/k or Ctrl-n/p moves through results. See the [Neovim navigation notes](../nvim/README.md#navigation).

New windows and splits start in the session's directory (set with `tmux new -s dev -c /path/to/project`), even after a shell changes directory.

A typical layout: window 1 for `nvim`, window 2 for `claude`, window 3 for git
and test runs. Give Claude a task, `C-a 1` back to the editor while it works.

## Surviving a reboot

Detaching survives a dropped connection, but not a restart — the server dies
with the machine. Two plugins cover that gap:

- [`tmux-resurrect`](https://github.com/tmux-plugins/tmux-resurrect) saves and
  restores the session, window and pane layout, and each pane's working
  directory.
- [`tmux-continuum`](https://github.com/tmux-plugins/tmux-continuum) runs it for
  you: a save every 15 minutes, and a restore when tmux next starts.

What is restored is the *shape* of your workspace, not its processes. Programs
are relaunched where supported; nothing is kept alive through the restart.

- `./install.sh tmux` installs the plugins, and updates them on every later run.
- Before a planned reboot, press `C-a C-s` for the freshest snapshot.
- After rebooting, just start `tmux`. If Continuum does not restore on its own,
  press `C-a C-r`.

## Copy and paste

Two clipboards are in play — your local machine's, and whatever tmux or Neovim
holds — which is the whole reason this needs explaining. The workflow is
deliberately simple:

| Want | Do |
| --- | --- |
| Paste from the system clipboard | `Cmd-V` (macOS) / `Ctrl-Shift-V` (Linux) |
| Copy a Neovim selection to the system clipboard | Select with `v`, then `Space y` |
| Copy the current Neovim line to the system clipboard | `Space Y` |
| Paste the system clipboard in local Neovim | `Space p` |
| Select terminal text in WezTerm | Hold `Shift` and drag; `Cmd-C` / `Ctrl-Shift-C` copies it |
| Select terminal text in tmux | Drag, double-click a word, or triple-click a line; `y` copies it |

tmux and terminal programs receive ordinary clicks and scrolling. In a shell pane, tmux selects text and keeps the selection after release; press `y` to copy or Escape to cancel. Mouse-aware applications such as Neovim handle their own selections. Hold `Shift` while dragging to bypass them and select text in WezTerm itself, then press `Cmd-C` (macOS) or `Ctrl-Shift-C` (Linux). Selecting, including double/triple clicks and rectangular selections, does not overwrite the clipboard.

**Over SSH.** OSC 52 lets explicit clipboard yanks in remote tmux or Neovim reach your laptop. Use a supporting terminal such as WezTerm, Kitty, Ghostty, or iTerm2. The Neovim provider is copy-only: paste with `Cmd-V` / `Ctrl-Shift-V`; `Space p` shows a reminder. The supported route is WezTerm → SSH → remote tmux/Neovim. Nesting a remote session inside local tmux requires a separate key-forwarding setup.

**Clear screen.** `C-l` is taken over for pane navigation, so the shell's clear-screen moves to `C-a C-l`.

## Config notes

**Colors.** The config sets `default-terminal` and truecolor overrides because the Catppuccin/Tokyonight setup uses `transparent = true`. Without them tmux advertises a lesser color capability and the colorscheme renders wrong.

**Autosave.** `focus-events on` is required: [`autosave.lua`](../nvim/lua/config/autosave.lua) writes the buffer on `FocusLost` and reloads externally-changed files on `FocusGained`. tmux swallows both events by default, so without it neither fires inside tmux.
