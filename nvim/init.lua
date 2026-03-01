-- Load (or install) lazy.nvim
require("config.lazy")

-- Set remaps and settings
require("config.set")
require("config.remap")

-- Git warnings: red badges for uncommitted changes / unpushed commits
require("config.git-warn").setup()

-- Load plugins
require("lazy").setup("plugins")

-- Enable LSP
vim.lsp.enable("luals")
