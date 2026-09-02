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
-- WezTerm's macOS clipboard update can occasionally leave the old contents in
-- place, so also send a completed selection through macOS's native pbcopy.
config.bypass_mouse_reporting_modifiers = 'SHIFT'

local function complete_selection(window, pane)
  local selection = window:get_selection_text_for_pane(pane)

  window:perform_action(
    act.CompleteSelectionOrOpenLinkAtMouseCursor 'Clipboard',
    pane
  )

  if wezterm.target_triple:find 'apple' and selection ~= '' then
    wezterm.background_child_process {
      '/bin/sh',
      '-c',
      'printf %s "$1" | /usr/bin/pbcopy',
      'wezterm-copy',
      selection,
    }
  end
end

config.mouse_bindings = {
  {
    event = { Up = { streak = 1, button = 'Left' } },
    -- When Shift bypasses tmux mouse reporting, WezTerm deliberately strips
    -- the modifier before matching this binding.
    mods = 'NONE',
    action = wezterm.action_callback(complete_selection),
  },
}

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
