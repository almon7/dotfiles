-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- Command navigation uses dedicated terminal keys; restore native Control keys.
for _, key in ipairs({ "<C-h>", "<C-j>", "<C-k>", "<C-l>" }) do
  vim.keymap.del("n", key)
end

-- Cmd-Up/Down arrives as Ctrl-F9/F10, or F33/F34 through tmux terminfo.
for _, mapping in ipairs({
  { "<C-F9>", "<C-y>", "up" },
  { "<F33>", "<C-y>", "up" },
  { "<C-F10>", "<C-e>", "down" },
  { "<F34>", "<C-e>", "down" },
}) do
  local key, scroll, direction = unpack(mapping)
  local opts = { desc = "Scroll " .. direction .. " one line" }
  vim.keymap.set({ "n", "x" }, key, scroll, opts)
  vim.keymap.set("i", key, "<C-o>" .. scroll, opts)
  vim.keymap.set("t", key, "<C-\\><C-n>" .. scroll, opts)
end

-- Recalculate one-third scrolling on each press so resized windows stay proportional.
-- Cmd-U/D arrives as Ctrl-F11/F12, or F35/F36 through tmux terminfo.
for _, mapping in ipairs({
  { "<C-d>", "<C-d>" },
  { "<C-u>", "<C-u>" },
  { "<C-F11>", "<C-u>" },
  { "<F35>", "<C-u>" },
  { "<C-F12>", "<C-d>" },
  { "<F36>", "<C-d>" },
}) do
  local shortcut, key = unpack(mapping)
  vim.keymap.set("n", shortcut, function()
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
vim.keymap.set("n", "<leader>fy", function()
  local function unavailable()
    vim.notify("No source file location in this buffer.", vim.log.levels.WARN)
  end

  local path = vim.api.nvim_buf_get_name(0)
  local root, file
  local suffix = ""
  local diffview = package.loaded["diffview.lib"]
  local view = diffview and diffview.get_current_view()
  if view and view.cur_layout then
    for _, win in ipairs(view.cur_layout.windows) do
      if win.id == vim.api.nvim_get_current_win() and win.file and win.file.bufnr == vim.api.nvim_get_current_buf() then
        file = win.file
        break
      end
    end
  end

  if file then
    if file.nulled or file.binary then
      return unavailable()
    end
    path, root = file.absolute_path, file.adapter.ctx.toplevel
    local rev = file.rev
    local types = require("diffview.vcs.rev").RevType
    if rev.type == types.COMMIT then
      suffix = " (git commit " .. rev.commit .. ")"
    elseif rev.type == types.STAGE then
      local stages = { "base", "ours", "theirs" }
      suffix = rev.stage == 0 and " (git index)" or (" (git index stage %d: %s)"):format(rev.stage, stages[rev.stage])
    elseif rev.type ~= types.LOCAL then
      return unavailable()
    end
  elseif vim.bo.buftype ~= "" or path == "" or path:match("^%a[%w+.-]*://") then
    return unavailable()
  else
    root = vim.fs.root(path, ".git")
    if not root then
      -- Config files can be opened through aliases such as ~/.config/nvim.
      path = vim.fn.resolve(path)
      root = vim.fs.root(path, ".git")
    end
  end

  if root then
    path = vim.fs.relpath(vim.fs.dirname(root), path)
  end
  if not path or path == "" or path:match("^%a[%w+.-]*://") then
    return unavailable()
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local location = ("%s:%d:%d%s"):format(path, cursor[1], cursor[2] + 1, suffix)
  if vim.fn.has("clipboard") == 0 then
    vim.notify("No system clipboard provider available.", vim.log.levels.ERROR)
    return
  end
  local ok, result = pcall(vim.fn.setreg, "+", location, "v")
  if not ok or result ~= 0 then
    vim.notify("Could not copy file location.", vim.log.levels.ERROR)
    return
  end
  vim.notify("Copied " .. location)
end, { desc = "Copy file location" })
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
