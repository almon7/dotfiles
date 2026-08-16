-- Pull in the wezterm API
local wezterm = require 'wezterm'

-- This will hold the configuration.
local config = wezterm.config_builder()

-- This is where you actually apply your config choices.
config.send_composed_key_when_left_alt_is_pressed = true
config.send_composed_key_when_right_alt_is_pressed = true
config.enable_kitty_keyboard = true

-- Use nerdfont
config.font = wezterm.font 'JetBrainsMono Nerd Font'

-- Finally, return the configuration to wezterm:
return config
