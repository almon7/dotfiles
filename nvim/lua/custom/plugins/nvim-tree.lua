vim.pack.add { 'https://github.com/nvim-tree/nvim-tree.lua' }

require('nvim-tree').setup {
  on_attach = function(bufnr)
    local api = require 'nvim-tree.api'
    -- A custom on_attach replaces the default mappings, so restore them before adding h/l.
    api.map.on_attach.default(bufnr)
    vim.keymap.del('n', '<C-k>', { buffer = bufnr }) -- Use the global pane navigation mapping.

    vim.keymap.set('n', 'h', function()
      local node = api.tree.get_node_under_cursor()
      -- Ignore non-node rows and the root; opening the root would move the tree up a directory.
      if not node or not node.parent then return end
      -- open.edit() toggles directories, so an open directory is collapsed here.
      if node.open then
        api.node.open.edit()
      else
        api.node.navigate.parent()
      end
    end, { buffer = bufnr, desc = 'Collapse directory or go to parent' })

    vim.keymap.set('n', 'l', function()
      local node = api.tree.get_node_under_cursor()
      -- Files have no open flag; skip open directories so l cannot toggle them closed.
      if node and not node.open then api.node.open.edit() end
    end, { buffer = bufnr, desc = 'Expand directory or open file' })
  end,
  -- Opening a file must not equalise the existing editor splits.
  view = { preserve_window_proportions = true },
  -- Follow buffer changes while retaining the current tree root.
  update_focused_file = { enable = true },
  renderer = {
    highlight_git = 'name',
    -- Keep file-type glyphs but let the monochrome theme supply their colour.
    icons = { web_devicons = { file = { color = false } } },
  },
}
