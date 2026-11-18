-- Exercise the configured outline with the installed Aerial plugin and Lua parser.
vim.opt.rtp:prepend(vim.fn.stdpath 'data' .. '/site/pack/core/opt/aerial.nvim')
vim.pack.add = function() end
dofile 'nvim/lua/custom/plugins/aerial.lua'

vim.api.nvim_buf_set_lines(0, 0, -1, false, {
  'local function first()',
  '  local function nested()',
  '    local function leaf() end',
  '    return leaf()',
  '  end',
  '  return nested()',
  'end',
  'local function second()',
  '  local function unrelated() end',
  'end',
  '-- outside either function',
})
vim.bo.filetype = 'lua'
local source = vim.api.nvim_get_current_win()
require('aerial').open { focus = false }
local function outline()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].filetype == 'aerial' then return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n') end
  end
  return ''
end
assert(vim.wait(3000, function() return outline():find 'unrelated' end), 'fixture symbols did not load')
require('aerial').tree_close_all()
assert(not outline():find 'nested' and not outline():find 'unrelated', 'fixture branches should start collapsed')

local function move(line, col, event)
  vim.api.nvim_win_set_cursor(source, { line, col })
  vim.api.nvim_exec_autocmds(event or 'CursorMoved', { buffer = vim.api.nvim_win_get_buf(source) })
end
move(11, 3)
assert(not outline():find 'unrelated', 'outside a symbol, the closest function should stay collapsed')
move(6, 4, 'CursorMovedI')
assert(outline():find 'nested' and not outline():find 'leaf', 'code after nested() should expand only first()')
require('aerial').tree_close_all()
move(4, 6)
assert(outline():find 'leaf', 'entering nested() should expand both first() and nested()')
assert(not outline():find 'unrelated', 'second() should stay collapsed')
assert(vim.api.nvim_get_current_win() == source, 'expanding the outline should preserve source focus')
require('aerial').tree_close_all()
vim.api.nvim_exec_autocmds('CursorHold', { buffer = vim.api.nvim_win_get_buf(source) })
assert(not outline():find 'nested', 'a stationary cursor should preserve a manually collapsed branch')
