# WezTerm

WezTerm provides the terminal, fonts, system clipboard, and OS shortcuts. tmux owns sessions and pane navigation; Neovim owns editing and its internal windows. The config uses JetBrainsMono Nerd Font and hides the tab bar when only one WezTerm tab is open.

## Keys and mouse

| Input | Behavior |
| --- | --- |
| Left Option | Sends Meta shortcuts, including Option-j/k for tmux sessions |
| Right Option | Composes symbols using the keyboard layout |
| Option-Left / Option-Right | Sends Alt-b / Alt-f for shell word movement |
| Option-3 | Types `#` for the British Mac keyboard layout |
| Cmd-C / Ctrl-Shift-C | Copies the WezTerm selection |
| Cmd-V / Ctrl-Shift-V | Pastes the system clipboard, including over SSH |
| Shift-drag | Selects in WezTerm, bypassing mouse-aware programs |
| Alt-drag / Shift-Alt-drag | Selects a rectangle; Shift bypasses mouse-aware programs |
| Ctrl-click | Opens a detected hyperlink, including inside tmux |

Selections never copy automatically on release, including word, line, extended, and rectangular selections. Normal mouse input reaches tmux or the running application. In tmux shell panes, drag/double/triple-click selects text for an explicit `y`; Shift selects in WezTerm for Cmd-C instead. See [tmux copy and paste](../tmux/README.md#copy-and-paste).

Option-key composition settings are for macOS. On Linux, use Alt for Meta shortcuts and Ctrl-Shift-C/V for clipboard actions.

## Integration and reloads

The keyboard configuration permits applications to request Kitty keyboard encoding. tmux negotiates extended keys with WezTerm and forwards modified keys such as Shift-Enter using CSI-u. Keep these paired settings together when troubleshooting input.

The installer sources WezTerm's shell integration in Bash or Zsh, but skips it in Neovim terminals to avoid visible escape sequences. tmux enables passthrough for supported metadata and focus events for Neovim autosave and external-file checks.

WezTerm automatically reloads its config when it changes; use Cmd-R or Ctrl-Shift-R to force a reload. Reload tmux separately with `C-a r`, and start a fresh Neovim session to load changed Lua mappings. Plugin versions remain pinned in Neovim's lockfile.

The supported remote route is WezTerm → SSH → remote tmux/Neovim. Clipboard copying uses OSC 52; paste stays with the local terminal. Local tmux wrapped around another remote tmux session needs its own forwarding policy.
