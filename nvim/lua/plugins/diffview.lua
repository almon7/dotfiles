return {
  {
    "sindrets/diffview.nvim",
    cmd = { "DiffviewOpen", "DiffviewClose", "DiffviewFileHistory", "DiffviewToggleFiles", "DiffviewFocusFiles" },
    opts = {},
    keys = {
      {
        "<leader>gvd",
        function()
          require("config.diffview").open()
        end,
        desc = "Uncommitted changes",
      },
      {
        "<leader>gvs",
        function()
          require("config.diffview").open(true)
        end,
        desc = "Staged changes",
      },
      {
        "<leader>gvr",
        function()
          require("config.diffview").branch()
        end,
        desc = "Review branch against base",
      },
      {
        "<leader>gvf",
        function()
          require("config.diffview").history(true)
        end,
        desc = "Current file history",
      },
      {
        "<leader>gvh",
        function()
          require("config.diffview").history()
        end,
        desc = "Repository history",
      },
      { "<leader>gvq", "<cmd>DiffviewClose<cr>", desc = "Close Diffview" },
      {
        "<leader>gvp",
        function()
          require("config.diffview").pr()
        end,
        desc = "Pick GitHub PR to view",
      },
      {
        "<leader>gvw",
        function()
          require("config.diffview").pr(true)
        end,
        desc = "Pick PR worktree to open in tmux",
      },
    },
  },
  {
    "folke/which-key.nvim",
    opts = function(_, opts)
      opts.spec = opts.spec or {}
      table.insert(opts.spec, { "<leader>gv", group = "Diffview" })
    end,
  },
}
