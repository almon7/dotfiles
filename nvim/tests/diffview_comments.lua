local api = vim.api
local root, directory = vim.env.DIFFVIEW_TEST_ROOT, vim.env.DIFFVIEW_TEST_DIR
local plugins = vim.fn.stdpath 'data' .. '/site/pack/core/opt/'
vim.opt.rtp:append(root .. '/nvim')
vim.opt.rtp:append(plugins .. 'nvim-treesitter/runtime')
vim.opt.rtp:append(plugins .. 'diffview.nvim')
vim.o.termguicolors = true
vim.o.laststatus = 0
vim.o.showtabline = 0
vim.o.ruler = false
vim.o.showmode = false
vim.cmd.colorscheme 'monochrome'
api.nvim_create_autocmd('FileType', {
  pattern = 'python',
  callback = function(event)
    vim.treesitter.start(event.buf, 'python')
    vim.treesitter.get_parser(event.buf):parse()
  end,
})
vim.cmd 'filetype on'
vim.pack.add = function() end -- Use installed plugins without package/network operations.
require 'custom.plugins.diffview'
vim.cmd.runtime 'plugin/diffview.lua'
vim.cmd.cd(directory)

local function settle()
  vim.cmd 'redraw!'
  vim.wait(60)
  vim.cmd 'redraw!'
end

local function windows()
  local result = {}
  for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
    local buf = api.nvim_win_get_buf(win)
    if vim.wo[win].diff and vim.bo[buf].filetype == 'python' then
      local first = api.nvim_buf_get_lines(buf, 0, 3, false)
      local side = table.concat(first, '\n'):match '"(.-)"'
      result[side] = win
    end
  end
  return result
end

local function wait_for_file(name)
  assert(
    vim.wait(3000, function()
      local found = windows()
      if not (found.old and found.new) then return false end
      for _, win in pairs(found) do
        if vim.fn.fnamemodify(api.nvim_buf_get_name(api.nvim_win_get_buf(win)), ':t') ~= name then return false end
        vim.wo[win].number, vim.wo[win].signcolumn, vim.wo[win].foldcolumn = false, 'no', '0'
        vim.wo[win].foldenable, vim.wo[win].cursorline = false, false
      end
      return true
    end),
    'Diffview did not load ' .. name
  )
  settle()
  return windows()
end

local function cell(win, row, col)
  local pos = vim.fn.screenpos(win, row, col)
  assert(pos.row > 0, 'Requested cell is not visible')
  return api.nvim__inspect_cell(1, pos.row - 1, pos.col - 1)[2]
end

local function colour(win, row, col, expected)
  local actual = cell(win, row, col)
  assert(actual.foreground == expected, ('row %d col %d: expected #%06x, got %s'):format(row, col, expected, vim.inspect(actual)))
  assert(not actual.dim, 'Comment must use an RGB colour, not the dim attribute')
end

local function check_pair(pair, offset)
  for side, win in pairs(pair) do
    local dark = side == 'old' and 0x9b4a59 or 0x52773d
    colour(win, 1 + offset, 10, side == 'old' and 0xf7768e or 0x9ece6a)
    for _, pos in ipairs { { 2, 3 }, { 4, 8 }, { 7, 20 } } do
      colour(win, pos[1] + offset, pos[2], dark)
    end
    colour(win, 5 + offset, 5, 0x9b9ea4)
    colour(win, 9 + offset, 3, 0x9b9ea4)
  end
end

local function run()
  vim.cmd 'DiffviewOpen HEAD~1..HEAD --selected-file=sample.py'
  local pair = wait_for_file 'sample.py'
  cell(pair.new, 2, 3) -- First inspection enables detailed highlight state.
  settle() -- Redraw before reading further attribute IDs.
  check_pair(pair, 0)
  vim.cmd.colorscheme 'monochrome'
  settle()
  check_pair(pair, 0)

  for _, win in pairs(pair) do
    api.nvim_win_set_cursor(win, { 50, 2 })
    api.nvim_win_call(win, function() vim.cmd 'normal! zt' end)
  end
  settle()
  colour(pair.old, 50, 3, 0x9b4a59)
  colour(pair.new, 50, 3, 0x52773d)
  require('diffview.actions').select_next_entry()
  pair = wait_for_file 'second.py'
  check_pair(pair, 2)

  vim.cmd 'DiffviewClose'
  vim.cmd 'DiffviewOpen HEAD~1..HEAD --imply-local --selected-file=sample.py'
  pair = wait_for_file 'sample.py'
  local win, buf = pair.new, api.nvim_win_get_buf(pair.new)
  api.nvim_set_hl(0, 'TestForeign', { bold = true })
  local foreign = vim.fn.matchaddpos('TestForeign', { { 1, 1, 5 } }, 10, -1, { window = win })
  local refs = api.nvim_create_namespace 'test-references'
  api.nvim_set_hl(0, 'LspReferenceText', { underline = true })
  api.nvim_buf_set_extmark(buf, refs, 1, 2, { end_row = 1, end_col = 5, hl_group = 'LspReferenceText', priority = 200 })
  settle()
  assert(cell(win, 2, 3).underline, 'Reference underline was lost')
  vim.fn.setreg('/', 'new')
  vim.o.hlsearch, vim.v.hlsearch = true, 1
  settle()
  assert(cell(win, 2, 3).background ~= nil, 'Search highlight was hidden')
  assert(cell(win, 2, 3).underline, 'Search removed reference underline')
  vim.cmd 'nohlsearch'
  api.nvim_buf_clear_namespace(buf, refs, 0, -1)

  api.nvim_buf_set_lines(buf, 1, 2, false, { 'other_value = "new"' })
  vim.cmd 'diffupdate'
  settle()
  colour(win, 2, 3, 0x9ece6a)
  assert(vim.iter(vim.fn.getmatches(win)):any(function(match) return match.id == foreign end), 'Unrelated match was removed')
  api.nvim_buf_set_lines(buf, 1, 2, false, { '# new standalone' })
  vim.cmd 'diffupdate'
  settle()
  colour(win, 2, 3, 0x52773d)

  vim.cmd 'tabnew'
  local normal = api.nvim_get_current_win()
  api.nvim_win_set_buf(normal, buf)
  settle()
  colour(normal, 2, 3, 0x9b9ea4)
  colour(normal, 4, 8, 0xe0e2ea)
  vim.cmd 'tabclose'
  api.nvim_set_current_win(win)
  return win
end

local function finish(ok, error)
  vim.fn.writefile({ vim.json.encode { ok = ok, error = error } }, directory .. '/result.json')
  vim.cmd 'qa!'
end

vim.defer_fn(function()
  local ok, win = xpcall(run, debug.traceback)
  if not ok then return finish(false, win) end
  vim.defer_fn(function()
    api.nvim_input ':diffoff<CR>'
    vim.defer_fn(function()
      local passed, error = xpcall(function()
        settle()
        assert(not vim.wo[win].diff, 'User diffoff command did not execute')
        colour(win, 2, 3, 0x9b9ea4)
      end, debug.traceback)
      finish(passed, error)
    end, 100)
  end, 200)
end, 100)
