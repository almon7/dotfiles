-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- Command navigation uses dedicated terminal keys; restore native Control keys.
for _, key in ipairs({ "<C-h>", "<C-j>", "<C-k>", "<C-l>" }) do
  vim.keymap.del("n", key)
end

-- Recalculate one-third scrolling on each press so resized windows stay proportional.
for _, key in ipairs({ "<C-d>", "<C-u>" }) do
  vim.keymap.set("n", key, function()
    if vim.v.count > 0 then
      return key .. "zz"
    end
    local lines = math.max(1, math.floor(vim.api.nvim_win_get_height(0) / 3))
    return lines .. key .. "zz"
  end, { expr = true, desc = "Scroll " .. (key == "<C-d>" and "down" or "up") .. " one third of a window" })
end

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

-- Use fixed English names so the date format does not depend on the locale.
vim.keymap.set("n", "<leader>id", function()
  local date = os.date("*t")
  local months = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sept", "Oct", "Nov", "Dec" }
  local weekdays = { "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" }
  local line = string.format("%02d %s %04d, %s", date.day, months[date.month], date.year, weekdays[date.wday])
  vim.api.nvim_put({ line }, "l", true, false)
end, { desc = "Insert today's date line" })
