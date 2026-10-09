-- Exercise the native picker without opening a terminal or changing a live font.
-- Run from the repository root: luajit wezterm/test_typeface.lua
package.loaded.wezterm = {
  action = setmetatable({}, {
    __index = function(_, name)
      return function(value) return { name = name, value = value } end
    end,
  }),
  config_builder = function() return {} end,
  default_hyperlink_rules = function() return {} end,
  action_callback = function(callback) return callback end,
  font = function(name) return name end,
}
local config = dofile(arg[1] or 'wezterm/.wezterm.lua')
assert(config.font == 'JetBrainsMono Nerd Font')
local picker
for _, binding in ipairs(config.keys) do
  if binding.key == 'f' and binding.mods == 'SHIFT|SUPER' then
    assert(binding.action.name == 'InputSelector')
    picker = binding.action.value
  end
end
assert(picker, 'Missing Cmd-Shift-F typeface picker')
assert(picker.title == 'Typeface (WezTerm window)')
assert(#picker.choices == 3)

local function new_window(overrides)
  return {
    overrides = overrides,
    updates = 0,
    get_config_overrides = function(self)
      if not self.overrides then return nil end
      local copy = {}
      for key, value in pairs(self.overrides) do
        copy[key] = value
      end
      return copy
    end,
    set_config_overrides = function(self, value)
      self.overrides = value
      self.updates = self.updates + 1
    end,
  }
end

local window = new_window()
local other_window = new_window { font = 'IntoneMono Nerd Font', font_size = 14 }
picker.action(window, {}, nil, nil)
assert(window.overrides == nil and window.updates == 0, 'Cancellation must not create overrides')

local fonts = { 'JetBrainsMono Nerd Font', 'IntoneMono Nerd Font', 'AtkynsonMono Nerd Font' }
local labels = { 'JetBrains Mono', 'Intel One Mono', 'Atkinson Hyperlegible Mono' }
for _, index in ipairs { 1, 2, 3, 1 } do
  local choice = picker.choices[index]
  assert(choice.id == fonts[index] and choice.label == labels[index])
  local updates = window.updates
  picker.action(window, {}, choice.id, choice.label)
  assert(window.overrides.font == fonts[index] and window.updates == updates + 1)
  if updates > 0 then assert(window.overrides.font_size == 17 and window.overrides.window_background_opacity == 0.9) end
  window.overrides.font_size, window.overrides.window_background_opacity = 17, 0.9
  local previous = window.overrides
  picker.action(window, {}, nil, nil)
  assert(window.overrides == previous and window.updates == updates + 1, 'Cancellation must preserve overrides')
  assert(other_window.overrides.font == 'IntoneMono Nerd Font' and other_window.updates == 0)
  assert(config.font == 'JetBrainsMono Nerd Font', 'New windows must keep the configured default')
end
print('PASS: native typeface picker, cancellation, preserved overrides and window isolation')
