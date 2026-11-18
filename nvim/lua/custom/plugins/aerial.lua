vim.pack.add { 'https://github.com/stevearc/aerial.nvim' }

require('aerial').setup {
  attach_mode = 'global',
  nerd_font = false,
  layout = {
    default_direction = 'right',
    placement = 'edge',
    width = 30,
    max_width = 30,
    resize_to_content = false,
  },
}

vim.keymap.set('n', '<leader>o', '<cmd>AerialToggle!<CR>', { desc = 'Toggle outline' })
