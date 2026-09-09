# WezTerm

WezTerm provides the terminal, fonts, system clipboard, and OS shortcuts. tmux owns sessions and pane navigation; Neovim owns editing and its internal windows. The config uses JetBrainsMono Nerd Font and hides the tab bar when only one WezTerm tab is open.

## Keys and mouse

| Input | Behavior |
| --- | --- |
| Left Option | Sends Meta shortcuts to the application |
| Right Option | Composes symbols using the keyboard layout |
| Option-Left / Option-Right | Sends Alt-b / Alt-f for shell word movement |
| Option-3 | Types `#` for the British Mac keyboard layout |
| Cmd-H/J/K/L | Moves left/down/up/right through tmux panes and Neovim splits |
| Cmd-N / Cmd-P | Next / previous tmux window in the session, wrapping at the ends |
| Cmd-] / Cmd-[ | Next / previous tmux session in name order, stopping at the ends |
| Ctrl-Shift-H / Ctrl-Shift-K / Ctrl-Shift-N | Hides WezTerm / clears WezTerm scrollback / creates a native WezTerm window |
| Cmd-C / Ctrl-Shift-C | Copies the terminal or tmux selection, clears its highlight, and keeps the scroll position |
| Cmd-V / Ctrl-Shift-V | Pastes the system clipboard, including over SSH |
| Left drag | In Neovim/Vim, resizes editor dividers or selects text in the editor; elsewhere, selects terminal text within the tmux pane without copying on release |
| Alt-drag | Explicitly bypasses application mouse reporting and selects in WezTerm across the terminal |
| Left click | Focuses the tmux pane and clears its terminal selection; in Neovim/Vim, also positions the editing cursor |
| Double-click / triple-click | Selects a word / line in Neovim/Vim or the tmux pane's terminal text |
| Shift-click / Shift-drag | Does nothing, including with other modifiers; preserves the selection and clipboard |
| Ctrl-click | Opens a detected hyperlink, including inside tmux |

tmux handles terminal selection outside Neovim/Vim so dragging across lines excludes neighboring panes without zooming. The terminal highlight survives release; copying clears the highlight and keeps the scroll position. Copying without a selection leaves the clipboard unchanged. Typing clears the terminal selection and sends the first key to the application; paste and scrolling also release the terminal selection. tmux temporarily holds the pane's displayed contents while highlighting text or browsing history. Typing and paste return to live input; clicking and dragging older output lets you select it without jumping to the bottom.

Neovim/Vim receives ordinary clicks and drags when it requests mouse input, including window-divider resizing. Copy a Neovim selection with `Space y`; `Cmd-C` / `Ctrl-Shift-C` copies terminal selections only. Shift-click and Shift-drag preserve the selection and clipboard. Ctrl-click opens links. The wheel scrolls applications that request mouse input; otherwise tmux scrolls the pane's retained terminal output, including Codex chats and shell output, without changing keyboard focus. Outside mouse-reporting applications, WezTerm handles normal text selection. Alt explicitly bypasses mouse reporting and therefore does not respect tmux pane boundaries. See [tmux copy and paste](../tmux/README.md#copy-and-paste).

Command navigation replaces WezTerm’s Cmd-H (hide), Cmd-K (clear scrollback), and Cmd-N (new native window); the Ctrl-Shift alternatives above remain available. Cmd-Shift-[/] still switches native WezTerm tabs. Ctrl-H/J/K/L and Option-J/K now reach applications without triggering pane or session navigation.

WezTerm sends Ctrl-F1/F2/F3/F4 for Command pane navigation, Ctrl-F5/F6 for windows, and Ctrl-F7/F8 for sessions. These terminal keys are reserved by the paired tmux and Neovim configuration, including over SSH; other terminal emulators must send the same keys to use this navigation. On Linux, `SUPER` is the Super/Windows modifier rather than Command. Window and session shortcuts require tmux.

Option-key composition settings are for macOS. On Linux, use Alt for Meta shortcuts and Ctrl-Shift-C/V for clipboard actions.

## Integration and reloads

The keyboard configuration permits applications to request Kitty keyboard encoding. tmux negotiates extended keys with WezTerm and forwards modified keys such as Shift-Enter using CSI-u. Keep these paired settings together when troubleshooting input.

The installer sources WezTerm's shell integration in Bash or Zsh, but skips it in Neovim terminals to avoid visible escape sequences. tmux enables passthrough for supported metadata and focus events for Neovim autosave and external-file checks.

WezTerm automatically reloads its config when it changes; use Cmd-R or Ctrl-Shift-R to force a reload. Reload tmux separately with `C-a r`, and start a fresh Neovim session to load changed Lua mappings. Plugin versions remain pinned in Neovim's lockfile.

The supported remote route is WezTerm → SSH → remote tmux/Neovim. Clipboard copying uses OSC 52; paste stays with the local terminal. Local tmux wrapped around another remote tmux session needs its own forwarding policy.

## Selection checks

`luajit wezterm/test_selection.lua` (from the repository root) checks copy/paste routing and mouse ownership without opening a GUI or changing the clipboard. WezTerm's `show-keys` command validates the real configuration. The [tmux integration checks](../tmux/README.md#selection-integration) exercise pane boundaries and input delivery.
