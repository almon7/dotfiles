-- Load (or install) lazy.nvim
require("config.lazy")

-- Set remaps and settings
require("config.set")
require("config.remap")

-- Load plugins
require("lazy").setup("plugins")

-- Enable LSP
vim.lsp.enable("luals")
