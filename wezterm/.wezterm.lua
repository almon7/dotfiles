-- Pull in the wezterm API
local wezterm = require 'wezterm'
local act = wezterm.action

-- This will hold the configuration.
local config = wezterm.config_builder()

-- This is where you actually apply your config choices.

-- Left Option is Meta, right Option composes symbols.
--
-- Forwarding ALT to the IME (to get # from Option+3 on a British layout) also
-- made the IME swallow Option+letter, so tmux never saw M-j/M-k. The IME wins
-- over key assignments for character-producing keys -- an OPT+j assignment
-- never matches, while OPT+LeftArrow does, because arrows are not composed.
-- So keep ALT out of the mask and give each Option key a distinct job.
config.macos_forward_to_ime_modifier_mask = 'SHIFT'
config.send_composed_key_when_left_alt_is_pressed = false
config.send_composed_key_when_right_alt_is_pressed = true
config.enable_kitty_keyboard = true
config.hide_tab_bar_if_only_one_tab = true

-- Mouse-aware programs receive normal clicks and scrolling. Hold Shift while
-- dragging when WezTerm itself should select terminal text.
config.bypass_mouse_reporting_modifiers = 'SHIFT'

config.mouse_bindings = {
  -- Open hyperlinks in the OS default browser with Ctrl-click. Define the
  -- binding for both regular panes and mouse-aware programs such as tmux.
  {
    event = { Down = { streak = 1, button = 'Left' } },
    mods = 'CTRL',
    mouse_reporting = false,
    action = act.Nop,
  },
  {
    event = { Up = { streak = 1, button = 'Left' } },
    mods = 'CTRL',
    mouse_reporting = false,
    action = act.OpenLinkAtMouseCursor,
  },
  {
    event = { Down = { streak = 1, button = 'Left' } },
    mods = 'CTRL',
    mouse_reporting = true,
    action = act.Nop,
  },
  {
    event = { Up = { streak = 1, button = 'Left' } },
    mods = 'CTRL',
    mouse_reporting = true,
    action = act.OpenLinkAtMouseCursor,
  },
  -- Releasing a WezTerm selection does not copy automatically. Cmd-C copies it.
  {
    event = { Up = { streak = 1, button = 'Left' } },
    mods = 'NONE',
    action = act.Nop,
  },
  {
    event = { Up = { streak = 2, button = 'Left' } },
    mods = 'NONE',
    action = act.Nop,
  },
  {
    event = { Up = { streak = 3, button = 'Left' } },
    mods = 'NONE',
    action = act.Nop,
  },
}

-- Match Terminal.app's word-wise cursor movement in shells and through tmux.
config.keys = {
  {
    key = 'v',
    mods = 'SUPER',
    action = act.PasteFrom 'Clipboard',
  },
  {
    key = 'LeftArrow',
    mods = 'OPT',
    action = act.SendKey { key = 'b', mods = 'ALT' },
  },
  {
    key = 'RightArrow',
    mods = 'OPT',
    action = act.SendKey { key = 'f', mods = 'ALT' },
  },
  -- The IME no longer composes Option+3 into #, and left Option is now Meta,
  -- so bind # explicitly. This matches either Option key, keeping # where it
  -- has always been rather than moving it to the right Option only.
  {
    key = '3',
    mods = 'OPT',
    action = act.SendString '#',
  },
}

-- Use nerdfont
config.font = wezterm.font 'JetBrainsMono Nerd Font'

-- Finally, return the configuration to wezterm:
return config
