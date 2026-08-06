-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

-- Separate system clipboard from Neovim's unnamed register to prevent unintended overwriting
vim.opt.clipboard = ""

-- Add winbar to show the file name and modified status in the window title bar
vim.opt.winbar = "%=%m %f"

-- Over SSH there is no local clipboard tool, so route the + and * registers
-- through OSC 52: the terminal carries the yank back to the client machine.
-- Needs a terminal that supports it (WezTerm, Kitty, Ghostty, iTerm2;
-- Alacritty must be told to) and `set -g set-clipboard on` in tmux.
--
-- Copy only. Most terminals refuse an OSC 52 read for security reasons, so
-- paste stays on the terminal's own Ctrl-Shift-V.
if vim.env.SSH_TTY or vim.env.SSH_CONNECTION then
  local osc52 = require("vim.ui.clipboard.osc52")
  vim.g.clipboard = {
    name = "OSC 52",
    copy = { ["+"] = osc52.copy("+"), ["*"] = osc52.copy("*") },
    paste = { ["+"] = function() return {} end, ["*"] = function() return {} end },
  }
end
