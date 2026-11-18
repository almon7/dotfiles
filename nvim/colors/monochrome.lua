vim.cmd.runtime 'colors/default.vim'
vim.g.colors_name = 'monochrome'

-- Keep the square opaque inside mini.map's transparent column.
vim.api.nvim_set_hl(0, 'MiniMapSymbolLine', { fg = vim.api.nvim_get_hl(0, { name = 'LineNr', link = false }).fg, blend = 0 })

-- Code uses the existing normal text colour.
for _, group in ipairs { 'Constant', 'Identifier', 'Function', 'Statement', 'PreProc', 'Type', 'Special', 'String' } do
  vim.api.nvim_set_hl(0, group, { link = 'Normal' })
end

-- NvimTree uses monochrome names and icons, with colour reserved for Git status.
for _, group in ipairs {
  'NvimTreeFolderName',
  'NvimTreeEmptyFolderName',
  'NvimTreeOpenedFolderName',
  'NvimTreeSymlinkFolderName',
  'NvimTreeFolderIcon',
  'NvimTreeExecFile',
  'NvimTreeImageFile',
} do
  vim.api.nvim_set_hl(0, group, { link = 'Normal' })
end

-- Git filename highlights inherit these icon groups; use coloured groups that the monochrome syntax overrides do not affect.
for group, target in pairs {
  NvimTreeGitNewIcon = 'GitSignsAdd',
  NvimTreeGitStagedIcon = 'GitSignsAdd',
  NvimTreeGitDirtyIcon = 'GitSignsChange',
  NvimTreeGitRenamedIcon = 'GitSignsChange',
  NvimTreeGitDeletedIcon = 'GitSignsDelete',
  NvimTreeGitMergeIcon = 'DiagnosticWarn',
} do
  vim.api.nvim_set_hl(0, group, { link = target })
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
