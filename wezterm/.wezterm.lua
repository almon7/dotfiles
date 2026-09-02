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

-- Match Terminal.app's word-wise cursor movement in shells and through tmux.
config.keys = {
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
