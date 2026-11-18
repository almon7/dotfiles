vim.pack.add { 'https://github.com/stevearc/aerial.nvim' }

local aerial = require 'aerial'

local function expand_current_branch(event)
  if vim.wo.diff or not aerial.is_open { bufnr = event.buf } then return end

  -- Aerial keeps each symbol's fold state in its internal tree.
  local tree = require('aerial.data').get(event.buf)
  -- An empty fold table means there are no hidden rows to reveal.
  if not tree or vim.tbl_isempty(tree.collapsed) then return end

  local window = require 'aerial.window'
  local line, col = unpack(vim.api.nvim_win_get_cursor(0))
  -- Search folded branches for the symbol that contains the cursor.
  local symbol = window.get_symbol_position(tree, line, col, true).exact_symbol
  local opened_fold = false
  while symbol do
    if tree:is_collapsed(symbol) then
      tree:set_collapsed(symbol, false)
      opened_fold = true
    end
    symbol = symbol.parent
  end
  if not opened_fold then return end

  -- Opening a fold changes the outline rows. Redraw once, then move the highlight to the new row.
  require('aerial.render').update_aerial_buffer(event.buf)
  window.update_all_positions(event.buf, 0)
end

aerial.setup {
  attach_mode = 'global',
  nerd_font = false,
  -- With on_attach set, Aerial needs lazy_load to wait until you first use it.
  lazy_load = true,
  on_attach = function(buf)
    -- React to cursor movement so a pause in the editor cannot reopen a branch you just closed.
    vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
      buffer = buf,
      callback = expand_current_branch,
      desc = 'Expand the current symbol in the outline',
    })
  end,
  layout = {
    default_direction = 'right',
    placement = 'edge',
    width = 30,
    -- Aerial caps the width at 20% of the editor by default, even with width set to 30.
    max_width = 30,
    resize_to_content = false,
  },
}

-- The ! in AerialToggle! keeps the cursor in the code window when the outline opens.
vim.keymap.set('n', '<leader>o', '<cmd>AerialToggle!<CR>', { desc = 'Toggle outline' })
