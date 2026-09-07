-- Seamless Ctrl-h/j/k/l between Neovim splits and tmux panes.
-- The tmux half of this lives in tmux/tmux.conf.
-- Harmless outside tmux — the keys just move between nvim windows.
local terminal_navigation = require("config.navigation").terminal

return {
  "christoomey/vim-tmux-navigator",
  init = function()
    vim.g.tmux_navigator_no_mappings = 1
    vim.g.tmux_navigator_no_wrap = 1
  end,
  cmd = {
    "TmuxNavigateLeft",
    "TmuxNavigateDown",
    "TmuxNavigateUp",
    "TmuxNavigateRight",
    "TmuxNavigatePrevious",
  },
  keys = {
    { "<c-h>", "<cmd>TmuxNavigateLeft<cr>", desc = "Go to left window/pane" },
    { "<c-j>", "<cmd>TmuxNavigateDown<cr>", desc = "Go to lower window/pane" },
    { "<c-k>", "<cmd>TmuxNavigateUp<cr>", desc = "Go to upper window/pane" },
    { "<c-l>", "<cmd>TmuxNavigateRight<cr>", desc = "Go to right window/pane" },
    { "<c-\\>", "<cmd>TmuxNavigatePrevious<cr>", desc = "Go to previous window/pane" },
    { "<c-h>", terminal_navigation("TmuxNavigateLeft"), mode = "t", expr = true, desc = "Go to left window/pane" },
    { "<c-j>", terminal_navigation("TmuxNavigateDown"), mode = "t", expr = true, desc = "Go to lower window/pane" },
    { "<c-k>", terminal_navigation("TmuxNavigateUp"), mode = "t", expr = true, desc = "Go to upper window/pane" },
    { "<c-l>", terminal_navigation("TmuxNavigateRight"), mode = "t", expr = true, desc = "Go to right window/pane" },
  },
}
