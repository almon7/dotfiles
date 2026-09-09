-- Seamless Cmd-h/j/k/l (sent by WezTerm as Ctrl-F1/F2/F3/F4) between Neovim splits and tmux panes.
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
  -- tmux terminfo decodes Ctrl-F1/F2/F3/F4 as F25/F26/F27/F28; direct Kitty input retains the modifier.
  keys = {
    { "<C-F1>", "<cmd>TmuxNavigateLeft<cr>", desc = "Go to left window/pane" },
    { "<F25>", "<cmd>TmuxNavigateLeft<cr>", desc = "Go to left window/pane" },
    { "<C-F2>", "<cmd>TmuxNavigateDown<cr>", desc = "Go to lower window/pane" },
    { "<F26>", "<cmd>TmuxNavigateDown<cr>", desc = "Go to lower window/pane" },
    { "<C-F3>", "<cmd>TmuxNavigateUp<cr>", desc = "Go to upper window/pane" },
    { "<F27>", "<cmd>TmuxNavigateUp<cr>", desc = "Go to upper window/pane" },
    { "<C-F4>", "<cmd>TmuxNavigateRight<cr>", desc = "Go to right window/pane" },
    { "<F28>", "<cmd>TmuxNavigateRight<cr>", desc = "Go to right window/pane" },
    { "<c-\\>", "<cmd>TmuxNavigatePrevious<cr>", desc = "Go to previous window/pane" },
    { "<C-F1>", terminal_navigation("TmuxNavigateLeft"), mode = "t", expr = true, desc = "Go to left window/pane" },
    { "<F25>", terminal_navigation("TmuxNavigateLeft"), mode = "t", expr = true, desc = "Go to left window/pane" },
    { "<C-F2>", terminal_navigation("TmuxNavigateDown"), mode = "t", expr = true, desc = "Go to lower window/pane" },
    { "<F26>", terminal_navigation("TmuxNavigateDown"), mode = "t", expr = true, desc = "Go to lower window/pane" },
    { "<C-F3>", terminal_navigation("TmuxNavigateUp"), mode = "t", expr = true, desc = "Go to upper window/pane" },
    { "<F27>", terminal_navigation("TmuxNavigateUp"), mode = "t", expr = true, desc = "Go to upper window/pane" },
    { "<C-F4>", terminal_navigation("TmuxNavigateRight"), mode = "t", expr = true, desc = "Go to right window/pane" },
    { "<F28>", terminal_navigation("TmuxNavigateRight"), mode = "t", expr = true, desc = "Go to right window/pane" },
  },
}
