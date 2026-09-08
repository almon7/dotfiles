# WezTerm

WezTerm provides the terminal, fonts, system clipboard, and OS shortcuts. tmux owns sessions and pane navigation; Neovim owns editing and its internal windows. The config uses JetBrainsMono Nerd Font and hides the tab bar when only one WezTerm tab is open.

## Keys and mouse

| Input | Behavior |
| --- | --- |
| Left Option | Sends Meta shortcuts, including Option-j/k for tmux sessions |
| Right Option | Composes symbols using the keyboard layout |
| Option-Left / Option-Right | Sends Alt-b / Alt-f for shell word movement |
| Option-3 | Types `#` for the British Mac keyboard layout |
| Cmd-C / Ctrl-Shift-C | Copies the terminal or tmux selection and keeps it highlighted |
| Cmd-V / Ctrl-Shift-V | Pastes the system clipboard, including over SSH |
| Left drag | Selects text across lines within the tmux pane, including over Codex and Neovim; release keeps the highlight without copying |
| Alt-drag | Explicitly bypasses application mouse reporting and selects in WezTerm across the terminal |
| Left click | Clears the previous selection and focuses the tmux pane |
| Double-click / triple-click | Selects a word / line within the tmux pane |
| Shift-click / Shift-drag | Does nothing, including with other modifiers; preserves the selection and clipboard |
| Ctrl-click | Opens a detected hyperlink, including inside tmux |

tmux handles ordinary selection so dragging across lines excludes neighboring panes without zooming. The highlight survives release and copying. Typing clears the selection and sends the first key to the application; paste and scrolling also release the selection. tmux temporarily holds the pane's displayed contents while highlighting text or browsing history. Typing and paste return to live input; clicking and dragging older output lets you select it without jumping to the bottom.

Shift-click and Shift-drag preserve the selection and clipboard. Ctrl-click opens links. Ordinary clicks focus tmux panes without moving Neovim's editing cursor. The wheel scrolls applications that request mouse input; otherwise tmux scrolls the pane's retained terminal output, including Codex chats and shell output, without changing keyboard focus. Outside mouse-reporting applications, WezTerm handles normal text selection. Alt explicitly bypasses mouse reporting and therefore does not respect tmux pane boundaries. See [tmux copy and paste](../tmux/README.md#copy-and-paste).

Option-key composition settings are for macOS. On Linux, use Alt for Meta shortcuts and Ctrl-Shift-C/V for clipboard actions.

## Integration and reloads

The keyboard configuration permits applications to request Kitty keyboard encoding. tmux negotiates extended keys with WezTerm and forwards modified keys such as Shift-Enter using CSI-u. Keep these paired settings together when troubleshooting input.

The installer sources WezTerm's shell integration in Bash or Zsh, but skips it in Neovim terminals to avoid visible escape sequences. tmux enables passthrough for supported metadata and focus events for Neovim autosave and external-file checks.

WezTerm automatically reloads its config when it changes; use Cmd-R or Ctrl-Shift-R to force a reload. Reload tmux separately with `C-a r`, and start a fresh Neovim session to load changed Lua mappings. Plugin versions remain pinned in Neovim's lockfile.

The supported remote route is WezTerm → SSH → remote tmux/Neovim. Clipboard copying uses OSC 52; paste stays with the local terminal. Local tmux wrapped around another remote tmux session needs its own forwarding policy.

## Selection checks

`luajit wezterm/test_selection.lua` (from the repository root) checks copy/paste routing and mouse ownership without opening a GUI or changing the clipboard. WezTerm's `show-keys` command validates the real configuration. The [tmux integration checks](../tmux/README.md#selection-integration) exercise pane boundaries and input delivery.
