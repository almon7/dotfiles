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

-- tmux receives ordinary mouse input and confines selection to its own panes.
-- Alt bypasses reporting; Shift must remain visible to the no-op bindings.
config.bypass_mouse_reporting_modifiers = 'ALT'

local mouse_bindings = {}
for _, mouse_reporting in ipairs { false, true } do
  -- Cover rapid-click streaks beyond the documented single/double/triple cases.
  for streak = 1, 32 do
    -- Outside mouse-reporting applications, WezTerm selects terminal text.
    -- Alt explicitly bypasses application mouse reporting.
    if not mouse_reporting then
      local selection_mode = streak == 2 and 'Word' or streak == 3 and 'Line' or 'Cell'
      for _, mods in ipairs { 'NONE', 'ALT' } do
        table.insert(mouse_bindings, {
          event = { Down = { streak = streak, button = 'Left' } },
          mods = mods,
          mouse_reporting = false,
          action = act.SelectTextAtMouseCursor(selection_mode),
        })
        table.insert(mouse_bindings, {
          event = { Drag = { streak = streak, button = 'Left' } },
          mods = mods,
          mouse_reporting = false,
          action = act.ExtendSelectionToMouseCursor(selection_mode),
        })
        table.insert(mouse_bindings, {
          event = { Up = { streak = streak, button = 'Left' } },
          mods = mods,
          mouse_reporting = false,
          action = act.Nop,
        })
      end
    end

    -- Suppress Shift even with other modifiers, preserving any selection.
    for _, mods in ipairs {
      'SHIFT', 'SHIFT|ALT', 'SHIFT|CTRL', 'SHIFT|SUPER',
      'SHIFT|ALT|CTRL', 'SHIFT|ALT|SUPER', 'SHIFT|CTRL|SUPER', 'SHIFT|ALT|CTRL|SUPER',
    } do
      for _, event in ipairs { 'Down', 'Drag', 'Up' } do
        table.insert(mouse_bindings, {
          event = { [event] = { streak = streak, button = 'Left' } },
          mods = mods,
          mouse_reporting = mouse_reporting,
          action = act.Nop,
        })
      end
    end

    -- Ctrl-click opens links without starting a selection in mouse-aware apps.
    for _, event in ipairs { 'Down', 'Drag', 'Up' } do
      table.insert(mouse_bindings, {
        event = { [event] = { streak = streak, button = 'Left' } },
        mods = 'CTRL',
        mouse_reporting = mouse_reporting,
        action = event == 'Up' and streak == 1 and act.OpenLinkAtMouseCursor or act.Nop,
      })
    end
  end
end

-- config_builder returns copies of tables: assign only after building the list.
config.mouse_bindings = mouse_bindings

-- tmux publishes this flag to the attached terminal, including over SSH.
-- The alternate-screen check also ignores stale state after returning to a shell.
local function has_tmux_selection(pane)
  return pane:is_alt_screen_active() and pane:get_user_vars().TMUX_SELECTION == '1'
end

local copy_selection = wezterm.action_callback(function(window, pane)
  if window:get_selection_text_for_pane(pane) ~= '' then
    window:perform_action(act.CopyTo 'Clipboard', pane)
    window:perform_action(act.ClearSelection, pane)
  elseif has_tmux_selection(pane) then
    window:perform_action(act.SendString '\x1b[99;13~', pane)
  end
end)

local paste_clipboard = wezterm.action_callback(function(window, pane)
  if has_tmux_selection(pane) then
    window:perform_action(act.SendString '\x1b[99;14~', pane)
  end
  window:perform_action(act.PasteFrom 'Clipboard', pane)
end)

-- Clipboard, shell editing, and Command navigation shortcuts.
config.keys = {
  -- Dedicated terminal keys keep Ctrl-h/j/k/l and Option-j/k available to apps. tmux and Neovim share this mapping, including through SSH.
  { key = 'h', mods = 'SUPER', action = act.SendKey { key = 'F1', mods = 'CTRL' } },
  { key = 'j', mods = 'SUPER', action = act.SendKey { key = 'F2', mods = 'CTRL' } },
  { key = 'k', mods = 'SUPER', action = act.SendKey { key = 'F3', mods = 'CTRL' } },
  { key = 'l', mods = 'SUPER', action = act.SendKey { key = 'F4', mods = 'CTRL' } },
  { key = 'n', mods = 'SUPER', action = act.SendKey { key = 'F5', mods = 'CTRL' } },
  { key = 'p', mods = 'SUPER', action = act.SendKey { key = 'F6', mods = 'CTRL' } },
  { key = ']', mods = 'SUPER', action = act.SendKey { key = 'F7', mods = 'CTRL' } },
  { key = '[', mods = 'SUPER', action = act.SendKey { key = 'F8', mods = 'CTRL' } },
  {
    key = 'c',
    mods = 'SUPER',
    action = copy_selection,
  },
  {
    key = 'c',
    mods = 'CTRL|SHIFT',
    action = copy_selection,
  },
  {
    key = 'v',
    mods = 'SUPER',
    action = paste_clipboard,
  },
  {
    key = 'v',
    mods = 'CTRL|SHIFT',
    action = paste_clipboard,
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
