-- Test copy/paste routing without opening a terminal or touching the clipboard.
local action = setmetatable({
  Nop = 'Nop',
  OpenLinkAtMouseCursor = 'OpenLinkAtMouseCursor',
  ClearSelection = 'ClearSelection',
}, {
  __index = function(_, name)
    return function(value)
      return { name = name, value = value }
    end
  end,
})
package.loaded.wezterm = {
  action = action,
  config_builder = function() return {} end,
  action_callback = function(callback) return callback end,
  font = function(name) return name end,
}
local config = dofile(arg[1] or 'wezterm/.wezterm.lua')
local function key_action(key, mods)
  for _, binding in ipairs(config.keys) do
    if binding.key == key and binding.mods == mods then return binding.action end
  end
  error('Missing key binding: ' .. mods .. '+' .. key)
end

local calls, text, selection, alt, clipboard = {}, '', '0', true, ''
local pane = {
  get_user_vars = function() return { TMUX_SELECTION = selection } end,
  is_alt_screen_active = function() return alt end,
}
local window = {
  get_selection_text_for_pane = function() return text end,
  perform_action = function(_, value, target)
    assert(target == pane)
    table.insert(calls, value)
    if value == 'ClearSelection' then
      text = ''
    elseif value.name == 'CopyTo' then
      clipboard = text
    end
  end,
}
for _, mods in ipairs { 'SUPER', 'CTRL|SHIFT' } do
  local copy = key_action('c', mods)
  calls, text, selection, alt = {}, '', '1', true
  copy(window, pane)
  assert(#calls == 1 and calls[1].name == 'SendString' and calls[1].value == '\x1b[99;13~')
  for _, tmux_state in ipairs { '0', '1' } do
    calls, text, selection, clipboard = {}, 'terminal selection', tmux_state, 'clipboard sentinel'
    copy(window, pane)
    assert(#calls == 2 and calls[1].name == 'CopyTo' and calls[1].value == 'Clipboard')
    assert(calls[2] == 'ClearSelection' and text == '')
    assert(clipboard == 'terminal selection', 'Copy must finish before clearing the selection')
    calls = {}
    copy(window, pane)
    assert(clipboard == 'terminal selection', 'Copy without a terminal selection must preserve the clipboard')
    if tmux_state == '1' then
      assert(#calls == 1 and calls[1].name == 'SendString' and calls[1].value == '\x1b[99;13~')
    else
      assert(#calls == 0)
    end
  end
  calls, text, selection = {}, '', '0'
  copy(window, pane)
  assert(#calls == 0)
  calls, selection, alt = {}, '1', false
  copy(window, pane)
  assert(#calls == 0, 'Stale tmux state must not send keys to the shell')

  local paste = key_action('v', mods)
  calls, selection, alt = {}, '1', true
  paste(window, pane)
  assert(#calls == 2 and calls[1].name == 'SendString' and calls[1].value == '\x1b[99;14~')
  assert(calls[2].name == 'PasteFrom' and calls[2].value == 'Clipboard')
  calls, selection = {}, '0'
  paste(window, pane)
  assert(#calls == 1 and calls[1].name == 'PasteFrom')
end

for _, binding in ipairs(config.mouse_bindings) do
  if binding.mods:find('SHIFT', 1, true) then
    assert(binding.action == 'Nop', 'Shift gestures must preserve selection and clipboard')
  end
  if binding.mods == 'NONE' or binding.mods == 'ALT' then
    assert(not binding.mouse_reporting, 'tmux must receive ordinary mouse events')
    if binding.event.Up then assert(binding.action == 'Nop') end
  end
end
print('PASS: copy clears selection, clipboard routing, stale-state guard, Shift suppression and tmux mouse ownership')
