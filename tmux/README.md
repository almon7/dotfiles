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
| `C-h/j/k/l` | Move between panes **and** Neovim splits, stopping at the outer edges |
| Left `Option-j` / `Option-k` | Next / previous session in name order, stopping at either end |
| `C-a a` | Return to the last window |
| `C-a C-a` | Send `C-a` to the program in the pane |
| `C-a H/J/K/L` | Move the current pane by swapping it left/down/up/right |
| `C-a z` | Zoom current pane fullscreen (toggle) |
| `C-a r` | Reload this config after editing it |
| `C-a C-s` / `C-a C-r` | Save / restore all tmux sessions |
| `C-a ?` | List every binding |

Click to focus a pane and drag to select text within that pane, including over Neovim and Codex. Drag borders to resize panes. The wheel scrolls applications that request mouse input, but does not open tmux history. Ctrl-click opens detected links in the OS browser.

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
| Select terminal text | Drag normally within the tmux pane; release keeps the highlight without copying |
| Copy selected terminal text | `Cmd-C` / `Ctrl-Shift-C`; the highlight remains |
| Clear the terminal selection | Type, paste, scroll, or click elsewhere; the first typed key reaches the application |

tmux selects continuously from the starting character to the ending character across lines, confined to the pane where the drag starts. No zooming or selection modifier is needed, including over Codex and Neovim. Double-click selects a word; triple-click selects a line within the pane. Shift-click and Shift-drag do nothing and preserve any existing selection and clipboard.

tmux uses copy mode internally to hold the highlight and the selected pane's displayed contents. Typing cancels selection and delivers the original key, including `h`, `j`, `k`, `l`, and `y`; no Escape or `q` is required. Cmd-C / Ctrl-Shift-C copies without clearing the highlight. Clipboard paste, scrolling, and clicking elsewhere clear selection before their normal action.

History entry shortcuts (`C-a [` and `C-a PageUp`), scrollbar actions, and pane context menus remain disabled. Scrolling over a shell clears selection but does not open history; mouse-aware applications retain wheel scrolling. Alt-drag explicitly selects in WezTerm and can cross pane boundaries. See [WezTerm mouse bindings](../wezterm/README.md#keys-and-mouse).

**Over SSH.** OSC 52 lets explicit clipboard yanks in remote tmux or Neovim reach your laptop. Use a supporting terminal such as WezTerm, Kitty, Ghostty, or iTerm2. The Neovim provider is copy-only: paste with `Cmd-V` / `Ctrl-Shift-V`; `Space p` shows a reminder. The supported route is WezTerm → SSH → remote tmux/Neovim. Nesting a remote session inside local tmux requires a separate key-forwarding setup.

**Clear screen.** `C-l` is taken over for pane navigation, so the shell's clear-screen moves to `C-a C-l`.

## Config notes

**Colors.** The config sets `default-terminal` and truecolor overrides because the Catppuccin/Tokyonight setup uses `transparent = true`. Without them tmux advertises a lesser color capability and the colorscheme renders wrong.

**Autosave.** `focus-events on` is required: [`autosave.lua`](../nvim/lua/config/autosave.lua) writes the buffer on `FocusLost` and reloads externally-changed files on `FocusGained`. tmux swallows both events by default, so without it neither fires inside tmux.

## Selection integration

`selection-state.sh`, linked at `~/.tmux/selection-state.sh`, publishes the active pane's copy-mode state as the `TMUX_SELECTION` WezTerm user variable via OSC 1337. The helper writes only a boolean to attached client terminals; selection text stays in tmux until explicit copying emits OSC 52. Indexed hooks update the flag on selection, focus, window/session changes, attach, detach, and reload. The helper receives the server socket explicitly so separate tmux servers use their own clients. Its Python 3 writer uses nonblocking terminal I/O and skips backed-up clients so a stalled SSH connection cannot hold up healthy clients. The tmux installer installs Python alongside tmux.

WezTerm sends the private sequences `ESC [ 99 ; 13 ~` (copy) and `ESC [ 99 ; 14 ~` (cancel before paste) only when the flag is active in the alternate screen. tmux reserves `user-keys[90]` / `User90` and `user-keys[91]` / `User91` for the bridge and consumes both harmlessly outside copy mode. These sequences are used because tmux does not accept F13/F14 key names. Both copy-mode key tables are replaced on reload so old bindings cannot consume typing.

Run `python3 tmux/test_mouse_selection.py` from the repository root for isolated two-pane terminal-protocol tests. The tests check selection boundaries, clipboard output, first-key delivery, navigation, paste, wheel scrolling, reload, and detach without touching the running server or the system clipboard. Run `luajit wezterm/test_selection.lua` to check the terminal-side copy/paste routing. Rendering, actual OS clipboard access, and Ctrl-click browser opening still need a WezTerm GUI check.
