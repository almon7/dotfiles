-- Pull in the wezterm API
local wezterm = require 'wezterm'
local act = wezterm.action

-- This will hold the configuration.
local config = wezterm.config_builder()

-- This is where you actually apply your config choices.

-- British layout: # is Option+3. use_ime defaults to true, and the IME forward
-- mask defaults to "SHIFT" only, so Option+key never reaches the IME to be
-- composed. Adding ALT lets macOS compose Option symbols as usual.
config.macos_forward_to_ime_modifier_mask = 'SHIFT|ALT'

-- Non-IME fallback path, in case use_ime is ever turned off. Both Options
-- compose symbols either way; the OPT+arrow assignments below still send
-- Alt/Meta, because key assignments are matched before the IME sees the key.
config.send_composed_key_when_left_alt_is_pressed = true
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
}

-- Use nerdfont
config.font = wezterm.font 'JetBrainsMono Nerd Font'

-- Finally, return the configuration to wezterm:
return config
