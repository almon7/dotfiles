-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

-- Separate system clipboard from Neovim's unnamed register to prevent unintended overwriting
vim.opt.clipboard = ""

-- Add winbar to show the file name and modified status in the window title bar
vim.opt.winbar = "%=%m %f"
