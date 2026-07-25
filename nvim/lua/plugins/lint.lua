return {
  {
    "mfussenegger/nvim-lint",
    config = function()
      local lint = require("lint")

      -- your existing lint setup (linters_by_ft, etc.)
      lint.linters_by_ft = {
        markdown = { "markdownlint" },
        -- ...
      }

      -- patch markdownlint args to disable MD013
      --lint.linters.markdownlint.args = { "--disable", "MD013", "--" }
      -- lint.linters.markdownlint.args = { "--stdin", "--disable", "MD013", "--" }
    end,
  },
}
