vim.pack.add { 'https://github.com/tpope/vim-fugitive' }

require 'custom.git_log'

vim.keymap.set('n', '<leader>gt', '<cmd>GitLog<CR>', { desc = 'Git tree (latest 200 commits)' })
require('which-key').add { { '<leader>g', group = 'Git' } }
