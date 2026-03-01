-- Line Numbers
vim.opt.nu = true
vim.opt.relativenumber = true
vim.opt.fillchars:append { eob = " " } -- remove ~ in empty lines

-- Indentation
vim.opt.tabstop = 4
vim.opt.softtabstop = 4
vim.opt.shiftwidth = 4
vim.opt.expandtab = true
vim.opt.smartindent = true

-- Line Wrapping
vim.opt.wrap = false

-- Search Settings
vim.opt.ignorecase = true -- Case insensitive searching
vim.opt.hlsearch = true -- Highlight search results
vim.opt.incsearch = true -- Show search results as you type

-- Appearance
vim.opt.termguicolors = true -- Enable true color support

-- set confirm: ask for confirmation when closing unsaved files
vim.opt.confirm = true

-- Autosave when leaving insert mode, changing text, or losing focus
vim.api.nvim_create_autocmd({ "InsertLeave", "TextChanged", "FocusLost" }, {
  pattern = "*",
  command = "silent! write",
})


-- Other Settings
vim.opt.scrolloff = 8 -- Keep 8 lines visible when scrolling
vim.opt.signcolumn = "yes" -- Always show the sign column
vim.opt.isfname:append("@-@") -- Include @-@ in file names

vim.opt.updatetime = 50 -- Decrease update time for better performance
vim.opt.colorcolumn = "80" -- Highlight column 80
vim.opt.laststatus = 3 -- Single global statusline (not one per split)

