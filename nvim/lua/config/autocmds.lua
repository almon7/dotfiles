-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")

require("config.autosave")

local function set_markdown_defaults(buf)
  vim.b[buf].completion = false
  vim.diagnostic.enable(false, { bufnr = buf })
end

vim.api.nvim_create_autocmd("FileType", {
  pattern = "markdown",
  callback = function(event)
    set_markdown_defaults(event.buf)
  end,
  desc = "Disable completions and diagnostics in Markdown files",
})

-- The initial buffer can get its filetype before this config loads on VeryLazy.
vim.schedule(function()
  if vim.bo.filetype == "markdown" then
    set_markdown_defaults(0)
  end
end)
