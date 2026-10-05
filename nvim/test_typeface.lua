-- Exercise the real picker and WezTerm handler without changing a live terminal.
-- Run: nvim --headless -u NONE -i NONE -l nvim/test_typeface.lua
local root = vim.fs.dirname(vim.fs.dirname(vim.fs.abspath(debug.getinfo(1, "S").source:sub(2))))
local events = {}
package.loaded.wezterm = {
  action = setmetatable({}, {
    __index = function(_, name)
      return function(value)
        return { name, value }
      end
    end,
  }),
  config_builder = function()
    return {}
  end,
  default_hyperlink_rules = function()
    return {}
  end,
  action_callback = function(callback)
    return callback
  end,
  font = function(name)
    return name
  end,
  on = function(name, callback)
    events[name] = callback
  end,
}
local config = dofile(root .. "/wezterm/.wezterm.lua")
assert(config.font == "JetBrainsMono Nerd Font")
local apply = assert(events["user-var-changed"])
local overrides, updates = nil, 0
local window = {
  get_config_overrides = function()
    return overrides and vim.deepcopy(overrides)
  end,
  set_config_overrides = function(_, value)
    overrides, updates = value, updates + 1
  end,
}
apply(window, {}, "NVIM_TYPEFACE", "Intel One Mono")
assert(overrides.font == "IntoneMono Nerd Font")
overrides.font_size, overrides.window_background_opacity = 17, 0.9
apply(window, {}, "OTHER_VARIABLE", "JetBrains Mono")
apply(window, {}, "NVIM_TYPEFACE", "unrecognised font")
assert(updates == 1)

vim.g.mapleader = " "
for _, key in ipairs({ "<C-h>", "<C-j>", "<C-k>", "<C-l>" }) do
  vim.keymap.set("n", key, "<Nop>")
end
vim.keymap.set("n", "<leader>uf", "<Nop>", { desc = "Global autoformat" })
vim.keymap.set("n", "<leader>uF", "<Nop>", { desc = "Buffer autoformat" })
Snacks = {
  toggle = function()
    return { map = function() end }
  end,
}
dofile(root .. "/nvim/lua/config/keymaps.lua")
local picker = vim.fn.maparg("<Space>ut", "n", false, true)
assert(picker.desc == "Typeface (WezTerm)")
assert(vim.fn.maparg("<Space>ut", "x") == "")
assert(vim.fn.maparg("<Space>uf", "n", false, true).desc == "Global autoformat")
assert(vim.fn.maparg("<Space>uF", "n", false, true).desc == "Buffer autoformat")
local fonts = { "JetBrainsMono Nerd Font", "IntoneMono Nerd Font", "AtkynsonMono Nerd Font" }
local selected, written = nil, {}
vim.ui.select = function(items, options, callback)
  assert(#items == 3 and options.prompt == "Typeface (WezTerm window)")
  callback(items[selected])
end
local function send(sequence)
  written[#written + 1] = sequence
end
for _, modern in ipairs({ true, false }) do
  vim.api.nvim_ui_send = modern and send or nil
  vim.api.nvim_chan_send = function(channel, sequence)
    assert(not modern and channel == vim.v.stderr)
    send(sequence)
  end
  for _, tmux in ipairs({ false, true }) do
    vim.env.TMUX = tmux and "/tmp/test-tmux,123,0" or nil
    selected, written = nil, {}
    picker.callback()
    assert(#written == 0, "Cancellation must not send a font change")
    for _, index in ipairs({ 1, 2, 3, 1 }) do
      selected, written = index, {}
      picker.callback()
      assert(#written == 1)
      local sequence = written[1]
      if tmux then
        assert(sequence:sub(1, 9) == "\027Ptmux;\027\027" and sequence:sub(-2) == "\027\\")
        sequence = sequence:sub(8, -3):gsub("\027\027", "\027")
      end
      local encoded = assert(sequence:match("^\027%]1337;SetUserVar=NVIM_TYPEFACE=([%w+/=]+)\007$"))
      apply(window, {}, "NVIM_TYPEFACE", vim.base64.decode(encoded))
      assert(overrides.font == fonts[index])
      assert(overrides.font_size == 17 and overrides.window_background_opacity == 0.9)
    end
  end
end
print("PASS: typeface picker, cancellation, direct/tmux transport, both Neovim APIs and preserved overrides")
