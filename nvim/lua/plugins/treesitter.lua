return {
  -- Core treesitter: parser installation and queries
  {
    "nvim-treesitter/nvim-treesitter",
    lazy = false,
    branch = "main",
    build = ":TSUpdate",
    config = function()
      -- Install parsers for these languages (async, non-blocking)
      require("nvim-treesitter").install({
        "bash",
        "c",
        "cpp",
        "css",
        "diff",
        "html",
        "javascript",
        "json",
        "jsonc",
        "lua",
        "luadoc",
        "markdown",
        "markdown_inline",
        "python",
        "query",  -- for treesitter query files themselves
        "regex",
        "toml",
        "tsx",
        "typescript",
        "vim",
        "vimdoc",
        "yaml",
      })

      -- Enable highlighting, folding, and indentation per filetype
      vim.api.nvim_create_autocmd("FileType", {
        callback = function(event)
          -- Skip very large files to avoid slowdowns
          local ok, stats = pcall(vim.uv.fs_stat, vim.api.nvim_buf_get_name(event.buf))
          if ok and stats and stats.size > 100 * 1024 then return end

          local ft = vim.bo[event.buf].filetype
          if ft == "" then return end
          local lang = vim.treesitter.language.get_lang(ft)
          if not lang then return end
          if not pcall(vim.treesitter.start, event.buf, lang) then return end

          vim.wo[0][0].foldexpr = "v:lua.vim.treesitter.foldexpr()"
          vim.wo[0][0].foldmethod = "expr"
          vim.wo[0][0].foldlevel = 99

          vim.bo.indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
        end,
      })
    end,
  },

  -- Text objects powered by treesitter (select/move by function, class, etc.)
  {
    "nvim-treesitter/nvim-treesitter-textobjects",
    branch = "main",
    event = "BufReadPost",
    dependencies = { "nvim-treesitter/nvim-treesitter" },
    config = function()
      require("nvim-treesitter-textobjects").setup({
        select = { lookahead = true },
        move  = { set_jumps = true },
      })

      local sel  = require("nvim-treesitter-textobjects.select")
      local move = require("nvim-treesitter-textobjects.move")
      local swap = require("nvim-treesitter-textobjects.swap")

      -- Select text objects (visual + operator-pending)
      local sel_maps = {
        { "af", "@function.outer" },    { "if", "@function.inner" },
        { "ac", "@class.outer" },       { "ic", "@class.inner" },
        { "aa", "@parameter.outer" },   { "ia", "@parameter.inner" },
        { "ai", "@conditional.outer" }, { "ii", "@conditional.inner" },
        { "al", "@loop.outer" },        { "il", "@loop.inner" },
      }
      for _, m in ipairs(sel_maps) do
        local key, query = m[1], m[2]
        vim.keymap.set({ "x", "o" }, key, function()
          sel.select_textobject(query, "textobjects")
        end)
      end

      -- Move to next/previous text objects
      local move_maps = {
        { "]f", move.goto_next_start,     "@function.outer" },
        { "]F", move.goto_next_end,       "@function.outer" },
        { "]c", move.goto_next_start,     "@class.outer" },
        { "]C", move.goto_next_end,       "@class.outer" },
        { "[f", move.goto_previous_start, "@function.outer" },
        { "[F", move.goto_previous_end,   "@function.outer" },
        { "[c", move.goto_previous_start, "@class.outer" },
        { "[C", move.goto_previous_end,   "@class.outer" },
      }
      for _, m in ipairs(move_maps) do
        local key, fn, query = m[1], m[2], m[3]
        vim.keymap.set({ "n", "x", "o" }, key, function()
          fn(query, "textobjects")
        end)
      end

      -- Swap parameters
      vim.keymap.set("n", "<leader>sn", function() swap.swap_next("@parameter.inner") end)
      vim.keymap.set("n", "<leader>sp", function() swap.swap_previous("@parameter.inner") end)
    end,
  },

  -- Shows current code context (function/class you're inside) at top of buffer
  {
    "nvim-treesitter/nvim-treesitter-context",
    event = "BufReadPost",
    dependencies = { "nvim-treesitter/nvim-treesitter" },
    opts = {
      enable            = true,
      max_lines         = 4,
      min_window_height = 20,
      mode              = "cursor",
      separator         = nil,
    },
  },
}
