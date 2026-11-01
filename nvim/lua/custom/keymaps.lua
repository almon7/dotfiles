-- Space e: Open Netrw
vim.keymap.set('n', '<leader>e', '<cmd>Explore<CR>', {
  desc = 'Open file explorer',
})

-- Register an alternative before netrw opens so it leaves Ctrl-H for window navigation.
vim.keymap.set('n', '<leader>nh', '<Plug>NetrwHideEdit', { desc = 'Netrw: edit hidden-file patterns' })

vim.api.nvim_create_autocmd('FileType', {
  group = vim.api.nvim_create_augroup('custom-netrw-keymaps', { clear = true }),
  pattern = 'netrw',
  callback = function(event)
    vim.keymap.set('n', 'h', '<Plug>NetrwTreeSqueeze', {
      buffer = event.buf,
      desc = 'Collapse containing directory',
    })
  end,
})

-- Space i d: insert today's date below the cursor.
vim.keymap.set('n', '<leader>id', function()
  vim.api.nvim_put({ os.date('%d %b %Y, %a') }, 'l', true, false)
end, { desc = "Insert today's date line" })

-- Space f y: copy the current file location to the system clipboard.
vim.keymap.set('n', '<leader>fy', function()
  local path = vim.api.nvim_buf_get_name(0)
  if vim.bo.buftype ~= '' or path == '' or path:match('^%a[%w+.-]*://') then
    vim.notify('No source file location in this buffer.', vim.log.levels.WARN)
    return
  end

  local root = vim.fs.root(path, '.git')
  if not root then
    -- Resolve aliases such as ~/.config/nvim.
    path = vim.fn.resolve(path)
    root = vim.fs.root(path, '.git')
  end

  if root then
    path = vim.fs.relpath(vim.fs.dirname(root), path) or path
  end

  local location = string.format(
    '%s:%d:%d', path, vim.fn.line('.'), vim.fn.col('.')
  )

  if vim.fn.has('clipboard') == 0 then
    vim.notify('No system clipboard provider available.', vim.log.levels.ERROR)
    return
  end

  local ok, result = pcall(vim.fn.setreg, '+', location, 'v')
  if not ok or result ~= 0 then
    vim.notify('Could not copy file location.', vim.log.levels.ERROR)
    return
  end

  vim.notify('Copied ' .. location)
end, { desc = 'Copy file location' })


-- Add <leader>i label
require('which-key').add {
  { '<leader>i', group = 'Insert' },
}
