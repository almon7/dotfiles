-- Seamless Ctrl-h/j/k/l between Neovim splits and tmux panes.
-- The tmux half of this lives in tmux/tmux.conf.
-- Harmless outside tmux — the keys just move between nvim windows.
return {
  "christoomey/vim-tmux-navigator",
  cmd = {
    "TmuxNavigateLeft",
    "TmuxNavigateDown",
    "TmuxNavigateUp",
    "TmuxNavigateRight",
  },
  keys = {
    { "<c-h>", "<cmd><C-U>TmuxNavigateLeft<cr>", desc = "Go to left window/pane" },
    { "<c-j>", "<cmd><C-U>TmuxNavigateDown<cr>", desc = "Go to lower window/pane" },
    { "<c-k>", "<cmd><C-U>TmuxNavigateUp<cr>", desc = "Go to upper window/pane" },
    { "<c-l>", "<cmd><C-U>TmuxNavigateRight<cr>", desc = "Go to right window/pane" },
    -- Load the plugin when navigation starts in a terminal buffer too. Once
    -- loaded, its native terminal mappings run the commands without leaving
    -- terminal mode.
    { "<c-h>", mode = "t", desc = "Go to left window/pane" },
    { "<c-j>", mode = "t", desc = "Go to lower window/pane" },
    { "<c-k>", mode = "t", desc = "Go to upper window/pane" },
    { "<c-l>", mode = "t", desc = "Go to right window/pane" },
  },
}
