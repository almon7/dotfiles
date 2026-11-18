vim.g.tmux_navigator_no_wrap = 1
vim.pack.add({ 'https://github.com/christoomey/vim-tmux-navigator' }, { load = true })

-- The plugin's terminal mappings use Vim's Ctrl-W prefix. Neovim would send it to the terminal job.
for key, direction in pairs { h = 'Left', j = 'Down', k = 'Up', l = 'Right' } do
  vim.keymap.set('t', '<C-' .. key .. '>', '<Cmd>TmuxNavigate' .. direction .. '<CR>', { desc = 'Navigate ' .. direction:lower() })
end
