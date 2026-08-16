-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")

require("config.autosave")

local function disable_markdown_completions(buf)
  -- Disable both Blink's completion menu and native Copilot suggestions.
  vim.b[buf].completion = false
  vim.lsp.inline_completion.enable(false, { bufnr = buf })
end

vim.api.nvim_create_autocmd("FileType", {
  pattern = "markdown",
  callback = function(event)
    disable_markdown_completions(event.buf)
  end,
  desc = "Disable completions in Markdown files",
})

-- The initial buffer can get its filetype before this config loads on VeryLazy.
vim.schedule(function()
  if vim.bo.filetype == "markdown" then
    disable_markdown_completions(0)
  end
end)
