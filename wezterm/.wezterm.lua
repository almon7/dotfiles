-- Pull in the wezterm API
local wezterm = require 'wezterm'
local act = wezterm.action

-- This will hold the configuration.
local config = wezterm.config_builder()

-- This is where you actually apply your config choices.
-- Left Option acts as Alt/Meta; right Option keeps macOS symbol composition.
config.send_composed_key_when_left_alt_is_pressed = false
config.send_composed_key_when_right_alt_is_pressed = true
config.enable_kitty_keyboard = true
config.hide_tab_bar_if_only_one_tab = true

-- Shift bypasses mouse-aware programs such as tmux and lets WezTerm select.
-- Completing the selection publishes it directly to the macOS clipboard.
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
  {
    event = { Up = { streak = 1, button = 'Left' } },
    -- When Shift bypasses tmux mouse reporting, WezTerm deliberately strips
    -- the modifier before matching this binding.
    mods = 'NONE',
    action = act.CompleteSelectionOrOpenLinkAtMouseCursor 'Clipboard',
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
}

-- Use nerdfont
config.font = wezterm.font 'JetBrainsMono Nerd Font'

-- Finally, return the configuration to wezterm:
return config
