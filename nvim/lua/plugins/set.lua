-- Line Numbers
vim.opt.nu = true
vim.opt.relativenumber = true
vim.opt.fillchars:append { eob = " " } -- remove ~ in empty lines
-- Swap line nymbers and sign column
vim.opt.signcolumn = "number"


-- Indentation
vim.opt.tabstop = 4
vim.opt.softtabstop = 4
vim.opt.shiftwidth = 4
vim.opt.expandtab = true
vim.opt.smartindent = true

-- Line Wrapping
vim.opt.wrap = false

-- Search Settings
-- vim.opt.ignorecase = true -- Case insensitive searching
vim.opt.hlsearch = true -- Highlight search results
vim.opt.incsearch = true -- Show search results as you type

-- Appearance
vim.opt.termguicolors = true -- Enable true color support


-- Other Settings
vim.opt.scrolloff = 8 -- Keep 8 lines visible when scrolling
vim.opt.signcolumn = "yes" -- Always show the sign column
vim.opt.isfname:append("@-@") -- Include @-@ in file names

vim.opt.updatetime = 50 -- Decrease update time for better performance
vim.opt.colorcolumn = "80" -- Highlight column 80

