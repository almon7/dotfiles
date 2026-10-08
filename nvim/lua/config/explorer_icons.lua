local M = {}

local highlights = {
  DotfilesExplorerText = { source = "Normal", text = true },
  DotfilesExplorerHiddenText = { source = "Normal", text = true, dim = true },
}

local function set_colour(name, spec)
  local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
  local muted = vim.api.nvim_get_hl(0, { name = "Comment", link = false }).fg or normal.fg or 0x808080
  local grey = (math.floor(muted / 65536) + math.floor(muted / 256) % 256 + muted % 256) / 3
  local source = spec.source and vim.api.nvim_get_hl(0, { name = spec.source, link = false }).fg
  local background = normal.bg or (vim.o.background == "light" and 0xffffff or 0)
  local weight = spec.text and 1 or 0.35
  local colour = 0
  for shift = 0, 16, 8 do
    local scale = 2 ^ shift
    local channel = source and ((1 - weight) * grey + weight * (math.floor(source / scale) % 256)) or grey
    if spec.dim then
      channel = 0.45 * channel + 0.55 * (math.floor(background / scale) % 256)
    else
      channel = 0.9 * channel + 0.1 * (math.floor(background / scale) % 256)
    end
    colour = colour + math.floor(channel + 0.5) * scale
  end
  if source and not spec.text then
    -- Mix towards equal-luminance grey in linear sRGB, so colour washes out
    -- without making the icon darker.
    local linear = {}
    for index = 1, 3 do
      local channel = (math.floor(colour / 2 ^ ((3 - index) * 8)) % 256) / 255
      linear[index] = channel <= 0.04045 and channel / 12.92 or ((channel + 0.055) / 1.055) ^ 2.4
    end
    local luminance = 0.2126 * linear[1] + 0.7152 * linear[2] + 0.0722 * linear[3]
    colour = 0
    for _, channel in ipairs(linear) do
      channel = 0.65 * channel + 0.35 * luminance
      local encoded = channel <= 0.0031308 and 12.92 * channel or 1.055 * channel ^ (1 / 2.4) - 0.055
      colour = colour * 256 + math.floor(encoded * 255 + 0.5)
    end
  end
  vim.api.nvim_set_hl(0, name, { fg = colour })
end

for name, spec in pairs(highlights) do
  set_colour(name, spec)
end
vim.api.nvim_create_autocmd("ColorScheme", {
  group = vim.api.nvim_create_augroup("ExplorerIconColours", { clear = true }),
  callback = function()
    for name, spec in pairs(highlights) do
      set_colour(name, spec)
    end
  end,
})

function M.format(item, picker)
  -- Keep Snacks' filename text, symlink targets and Git/diagnostic indicators.
  -- This source supplies its own file icons and compacts the tree indentation.
  local result = Snacks.picker.format.file(item, picker)
  for _, part in ipairs(result) do
    if part[2] == "SnacksPickerTree" then
      local depth, parent = 0, item.parent
      while parent do
        depth, parent = depth + 1, parent.parent
      end
      part[1] = string.rep(" ", depth)
    end
    for _, marker in ipairs(part.virt_text or {}) do
      if type(marker[2]) == "string" and marker[2]:match("^SnacksPickerGitStatus") then
        marker[2] = "DotfilesExplorerText"
      end
    end
  end
  if not item.file then
    return result
  end

  for index, part in ipairs(result) do
    if part.field == "file" then
      local glyph, source
      local file_icons = picker.opts.icons.files
      if item.dir then
        glyph = item.open and file_icons.dir_open or file_icons.dir
      else
        glyph, source = Snacks.util.icon(item.file, "file", { fallback = file_icons })
      end
      local dot_entry = vim.fs.basename(item.file):sub(1, 1) == "."
      local icon_hl = "DotfilesExplorerIcon" .. (source or "Grey"):gsub("%W", "_") .. (dot_entry and "Hidden" or "")
      if not highlights[icon_hl] then
        highlights[icon_hl] = { source = source, dim = dot_entry }
        set_colour(icon_hl, highlights[icon_hl])
      end
      part[2] = dot_entry and "DotfilesExplorerHiddenText" or "DotfilesExplorerText"
      table.insert(result, index, { vim.trim(glyph) .. " ", icon_hl, virtual = true })
      break
    end
  end
  return result
end

return M
