return {
  {
    "sindrets/diffview.nvim",
    cmd = { "DiffviewOpen", "DiffviewClose", "DiffviewFileHistory", "DiffviewToggleFiles", "DiffviewFocusFiles" },
    opts = {
      hooks = {
        diff_buf_win_enter = function(_, _, ctx)
          vim.opt_local.fillchars:append({ diff = " " })
          local highlights = { DiffDelete = "DiffviewMutedDelete" }
          if ctx.layout_name:match("^diff2_") then
            local side = ctx.symbol == "a" and "DiffviewMutedDelete" or "DiffviewMutedAdd"
            highlights.DiffAdd = side
            highlights.DiffChange = side
            highlights.DiffText = side .. "Text"
            highlights.DiffTextAdd = side .. "Text"
          end
          vim.opt_local.winhighlight:append(highlights)
        end,
      },
    },
    config = function(_, opts)
      local function set_highlights()
        for name, background in pairs({
          DiffviewMutedDelete = "#35272D",
          DiffviewMutedAdd = "#27372E",
          DiffviewMutedDeleteText = "#49323A",
          DiffviewMutedAddText = "#344B3C",
        }) do
          vim.api.nvim_set_hl(0, name, { bg = background })
        end
      end

      vim.api.nvim_create_autocmd("ColorScheme", {
        group = vim.api.nvim_create_augroup("DiffviewMutedColours", { clear = true }),
        callback = set_highlights,
      })
      set_highlights()
      require("diffview").setup(opts)
    end,
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
        desc = "Pick GitHub PR and viewer",
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
      table.insert(opts.spec, { "<leader>gv", group = "Git view" })
    end,
  },
}
