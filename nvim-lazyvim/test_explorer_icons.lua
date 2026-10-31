-- Offline icon-provider and formatter tests; no plugins or network required.
-- Run: nvim --headless -u NONE -i NONE -l nvim/test_explorer_icons.lua
local config = vim.fs.dirname(vim.fs.abspath(debug.getinfo(1, "S").source:sub(2)))
local picker = { opts = { icons = { files = { enabled = false, dir = "󰉋 ", dir_open = "󰝰 " } } } }
local function stock_format(item, opts)
  assert(opts.opts.icons.files.enabled == false)
  if not item.file then
    return { { "No file", "Normal" } }
  end
  return {
    { "  ", "SnacksPickerTree" },
    { col = 0, virt_text = { { "!", "SnacksPickerGitStatusModified" }, { " " } }, virt_text_pos = "right_align" },
    { col = 0, virt_text = { { "!", "DiagnosticWarn" } }, virt_text_pos = "right_align" },
    {
      vim.fs.basename(item.file),
      item.filename_hl or (item.dir and "SnacksPickerDirectory" or "SnacksPickerFile"),
      field = "file",
    },
    { " -> target", "SnacksPickerLink" },
  }
end
local provider_calls = {}
local supplied_icons = {
  ["/tmp/main.py"] = { "󰌠", "TestPythonIcon" },
  ["/tmp/.hidden.py"] = { "󰌠", "TestPythonIcon" },
  ["/tmp/.config/main.py"] = { "󰌠", "TestPythonIcon" },
  ["/tmp/app.ts"] = { "󰛦", "TestDataIcon" },
  ["/tmp/init.lua"] = { "󰢱", "TestDataIcon" },
  ["/tmp/data.json"] = { "󰘦", "TestDataIcon" },
  ["/tmp/yellow.txt"] = { "󰈔", "TestYellowIcon" },
}
Snacks = {
  picker = { format = { file = stock_format } },
  util = {
    icon = function(path, category, opts)
      assert(category == "file")
      assert(opts.fallback == picker.opts.icons.files)
      provider_calls[#provider_calls + 1] = path
      return unpack(supplied_icons[path] or { "󰈔" })
    end,
  },
}
vim.o.background = "dark"
vim.api.nvim_set_hl(0, "Normal", { fg = "#c0c0c0", bg = "#202020" })
vim.api.nvim_set_hl(0, "Comment", { fg = "#808080" })
vim.api.nvim_set_hl(0, "NonText", { fg = "#505050" })
vim.api.nvim_set_hl(0, "TestPythonIcon", { fg = "#a1d971" })
vim.api.nvim_set_hl(0, "TestDataIcon", { fg = "#c280b6" })
vim.api.nvim_set_hl(0, "TestYellowIcon", { fg = "#ffd43b" })
local text_highlights = {}
for _, name in ipairs({
  "Normal",
  "Comment",
  "NonText",
  "SnacksPickerFile",
  "SnacksPickerPathIgnored",
  "SnacksPickerGitStatusModified",
  "DiagnosticWarn",
}) do
  text_highlights[name] = vim.api.nvim_get_hl(0, { name = name, link = false })
end
local winblend, pumblend = vim.wo.winblend, vim.o.pumblend
local icons = dofile(config .. "/lua/config/explorer_icons.lua")

local function icon(path, extra)
  local item = vim.tbl_extend("force", { file = path }, extra or {})
  local result = icons.format(item, picker)
  local added = table.remove(result, 4)
  local expected = stock_format(item, picker)
  expected[1][1] = item.parent and " " or ""
  expected[2].virt_text[1][2] = "DotfilesExplorerText"
  expected[4][2] = vim.fs.basename(path):sub(1, 1) == "." and "DotfilesExplorerHiddenText" or "DotfilesExplorerText"
  assert(vim.deep_equal(result, expected), "Only indentation, file icons, names and Git marker colours should change")
  assert(added[2]:match("^DotfilesExplorerIcon"), "File-type icons must retain their separate tint")
  assert(added.virtual == true, "Icons must not enter searchable filename text")
  assert(Snacks.picker.format.file == stock_format, "Other pickers must retain the stock formatter")
  return added[1], added[2]
end

-- Last-child branches must use the same one-column spacing as their siblings.
for _, last in ipairs({ false, true }) do
  local item = { file = "/tmp/main.py", last = last }
  for depth = 0, 8 do
    assert(icons.format(item, picker)[1][1] == string.rep(" ", depth), "Expected one space per folder level")
    item = { file = "/tmp/main.py", parent = item, last = last }
  end
end

local function expect(path, codepoint, extra)
  local glyph, hl = icon(path, extra)
  assert(glyph == vim.fn.nr2char(codepoint) .. " ", "Unexpected icon for " .. path)
  return hl
end

local source = expect("/tmp/main.py", 0xf0320)
assert(provider_calls[#provider_calls] == "/tmp/main.py", "Pass the original full path to the icon provider")
expect("/tmp/app.ts", 0xf06e6)
expect("/tmp/init.lua", 0xf08b1)
expect("/tmp/unknown.unknown-filetype", 0xf0214)
expect("/tmp/no-extension", 0xf0214)
local data = expect("/tmp/data.json", 0xf0626)
local calls_before_folders = #provider_calls
local folder = expect("/tmp/package.json", 0xf024b, { dir = true })
expect("/tmp/package.json", 0xf0770, { dir = true, open = true })
assert(#provider_calls == calls_before_folders, "Folders must use the standard solid folder symbols")

local function foreground(group)
  return assert(vim.api.nvim_get_hl(0, { name = group, link = false }).fg)
end
local source_colour = foreground(source)
local function luminance_and_spread(colour)
  local channels, luminance = {}, 0
  for index, weight in ipairs({ 0.2126, 0.7152, 0.0722 }) do
    local value = math.floor(colour / 2 ^ ((3 - index) * 8)) % 256
    channels[index] = value
    value = value / 255
    luminance = luminance + weight * (value <= 0.04045 and value / 12.92 or ((value + 0.055) / 1.055) ^ 2.4)
  end
  return luminance, math.max(unpack(channels)) - math.min(unpack(channels))
end
local yellow = expect("/tmp/yellow.txt", 0xf0214)
-- Baselines include the 10% dimming, before linear-sRGB desaturation.
for _, sample in ipairs({ { source_colour, 0x819272 }, { foreground(yellow), 0x9e9161 } }) do
  local actual_luminance, actual_spread = luminance_and_spread(sample[1])
  local baseline_luminance, baseline_spread = luminance_and_spread(sample[2])
  assert(math.abs(actual_luminance - baseline_luminance) < 0.003, "Desaturation must preserve the adjusted brightness")
  assert(actual_spread < baseline_spread * 0.8, "Icon colours should be noticeably more washed out")
end
local label_highlight = vim.api.nvim_get_hl(0, { name = "DotfilesExplorerText", link = false })
assert(label_highlight.fg == 0xb0b0b0, "Normal labels and Git markers should blend 10% towards the background")
assert(label_highlight.bg == nil, "Labels and Git markers must not copy Normal's background")
assert(source_colour ~= foreground(data), "File-type colours must be retained")
assert(foreground(folder) == 0x767676, "Solid folder icons should be slightly darker but stay neutral grey")

local ignored = expect("/tmp/main.py", 0xf0320, { filename_hl = "SnacksPickerPathIgnored" })
local hidden = expect("/tmp/.hidden.py", 0xf0320, { filename_hl = "SnacksPickerPathHidden" })
expect("/tmp/main.py", 0xf0320, { filename_hl = "SnacksPickerGitStatusUntracked" })
expect("/tmp/main.py", 0xf0320, { filename_hl = "SnacksPickerGitStatusModified" })
local ignored_folder = expect("/tmp/folder", 0xf024b, { dir = true, filename_hl = "SnacksPickerPathIgnored" })
local hidden_folder = expect("/tmp/.config", 0xf024b, { dir = true })
expect("/tmp/.config", 0xf0770, { dir = true, open = true })
local hidden_colour = foreground(hidden)
for shift = 0, 16, 8 do
  local ordinary = math.floor(source_colour / 2 ^ shift) % 256
  local dimmed = math.floor(hidden_colour / 2 ^ shift) % 256
  assert(dimmed < ordinary * 0.65 and dimmed > ordinary * 0.4, "Dotfile icons should be much darker")
end
assert(ignored == source and ignored_folder == folder, "Git ignore status must not dim entries")
assert(foreground(hidden_folder) < foreground(folder), "Dotfolders should be darker too")
assert(foreground(hidden_folder) == 0x4b4b4b, "Dotfolder icons should blend 55% towards the background")
local hidden_text_colour = foreground("DotfilesExplorerHiddenText")
assert(hidden_text_colour == 0x686868, "Dotfile names should be dimmed without any file-type tint")
local hidden_ignored = expect("/tmp/.hidden.py", 0xf0320, {
  filename_hl = "SnacksPickerPathIgnored",
  parent = { hidden = true },
})
assert(hidden_ignored == hidden, "Dotfiles should be dimmed equally regardless of Git status")
local inside_hidden = expect("/tmp/.config/main.py", 0xf0320, {
  filename_hl = "SnacksPickerPathHidden",
  parent = { hidden = true },
})
assert(inside_hidden == source, "Regular files must not inherit a dotfolder's dimming")
for name, highlight in pairs(text_highlights) do
  assert(
    vim.deep_equal(highlight, vim.api.nvim_get_hl(0, { name = name, link = false })),
    "Text highlight changed: " .. name
  )
end
assert(vim.wo.winblend == winblend and vim.o.pumblend == pumblend, "Opacity options must not change")
vim.api.nvim_set_hl(0, "Normal", { fg = "#eeddcc" })
vim.api.nvim_set_hl(0, "Comment", { fg = "#606060" })
vim.api.nvim_set_hl(0, "TestPythonIcon", { fg = "#d04040" })
vim.api.nvim_exec_autocmds("ColorScheme", {})
assert(foreground("Normal") == 0xeeddcc, "The text and Git-marker colour must remain theme-owned")
assert(foreground("DotfilesExplorerText") == 0xd6c7b8, "Labels must follow the new theme with the slight dimming")
assert(vim.api.nvim_get_hl(0, { name = "DotfilesExplorerText", link = false }).bg == nil)
assert(foreground(source) ~= source_colour, "File-type tints must follow theme changes")
assert(foreground("DotfilesExplorerHiddenText") ~= hidden_text_colour, "Dotfile text must follow theme changes")
assert(
  vim.api.nvim_get_hl(0, { name = hidden, link = false }).fg ~= hidden_colour,
  "Dotfile icons must follow theme changes"
)
assert(vim.deep_equal(icons.format({}, picker), stock_format({}, picker)))

-- Keep the integration limited to the explorer and prevent duplicate provider icons.
package.loaded["config.navigation"] = { terminal = function() end }
local spec = dofile(config .. "/lua/plugins/snacks.lua")
local explorer = spec.opts.picker.sources.explorer
assert(type(explorer.format) == "function")
assert(explorer.icons.files.enabled == false)
assert(explorer.formatters.file.filename_only == true)
assert(explorer.formatters.file.git_status_hl == false)
assert(spec.opts.picker.sources.files.format == nil)
assert(explorer.icons.git.ignored == "" and explorer.win.list.keys.gi[1] == "toggle_ignored_icons")
print("Explorer icon tests passed")
