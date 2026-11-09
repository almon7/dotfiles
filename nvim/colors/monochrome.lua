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
vim.api.nvim_set_hl(0, 'DiffComment', { fg = vim.api.nvim_get_hl(0, { name = 'Comment', link = false }).fg, dim = true })
vim.api.nvim_set_hl(0, 'DiffCommentAdd', { fg = '#52773d' })
vim.api.nvim_set_hl(0, 'DiffCommentDelete', { fg = '#9b4a59' })

-- Underline same variable and function
vim.api.nvim_set_hl(0, 'LspReferenceText', { underline = true })
