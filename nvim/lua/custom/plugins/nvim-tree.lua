vim.pack.add { 'https://github.com/nvim-tree/nvim-tree.lua' }

require('nvim-tree').setup {
  on_attach = function(bufnr)
    local api = require 'nvim-tree.api'
    api.map.on_attach.default(bufnr)

    vim.keymap.set('n', 'h', function()
      local node = api.tree.get_node_under_cursor()
      if not node or not node.parent then return end
      if node.open then
        api.node.open.edit()
      else
        api.node.navigate.parent()
      end
    end, { buffer = bufnr, desc = 'Collapse directory or go to parent' })

    vim.keymap.set('n', 'l', function()
      local node = api.tree.get_node_under_cursor()
      if node and not node.open then api.node.open.edit() end
    end, { buffer = bufnr, desc = 'Expand directory or open file' })
  end,
  view = { preserve_window_proportions = true },
  update_focused_file = { enable = true },
  renderer = {
    highlight_git = 'name',
    icons = { web_devicons = { file = { color = false } } },
  },
}
