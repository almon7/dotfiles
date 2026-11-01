vim.cmd.runtime 'colors/default.vim'
vim.g.colors_name = 'monochrome'

-- Code uses the existing normal text colour.
for _, group in ipairs { 'Constant', 'Identifier', 'Function', 'Statement', 'PreProc', 'Type', 'Special', 'String' } do
  vim.api.nvim_set_hl(0, group, { link = 'Normal' })
end

-- Comments, including TODO annotations, use the existing grey.
for _, group in ipairs { 'SpecialComment', 'Todo', '@comment.error', '@comment.warning', '@comment.note', '@comment.todo' } do
  vim.api.nvim_set_hl(0, group, { link = 'Comment' })
end

-- Diff Colours
vim.api.nvim_set_hl(0, 'DiffAdd', { fg = '#9ece6a', bg = 'NONE' })
vim.api.nvim_set_hl(0, 'DiffDelete', { fg = '#f7768e', bg = 'NONE' })
vim.api.nvim_set_hl(0, 'DiffChange', { bg = 'NONE' })
