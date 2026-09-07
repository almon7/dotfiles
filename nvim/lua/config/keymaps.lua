-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

vim.keymap.set("n", "<C-d>", "<C-d>zz") -- Center the cursor after scrolling down half a page
vim.keymap.set("n", "<C-u>", "<C-u>zz") -- Center the cursor after scrolling up half a page

vim.keymap.set("n", "n", "nzzzv") -- Center and reveal the next search match
vim.keymap.set("n", "N", "Nzzzv") -- Center and reveal the previous search match

-- Keep regular yanks private to Neovim; use Space-y/p when crossing the
-- system clipboard boundary.
vim.keymap.set({ "n", "x" }, "<leader>y", '"+y', { desc = "Copy to system clipboard" })
vim.keymap.set("n", "<leader>Y", '"+yy', { desc = "Copy line to system clipboard" })
if vim.env.SSH_TTY or vim.env.SSH_CONNECTION then
  vim.keymap.set({ "n", "x" }, "<leader>p", function()
    vim.notify("Over SSH, paste with your terminal: Cmd-V on macOS or Ctrl-Shift-V on Linux.", vim.log.levels.INFO)
  end, { desc = "Show terminal paste shortcut (SSH)" })
else
  vim.keymap.set({ "n", "x" }, "<leader>p", '"+p', { desc = "Paste from system clipboard" })
end
