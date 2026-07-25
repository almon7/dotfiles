return {
  "folke/snacks.nvim",
  opts = {
    picker = {
      sources = {
        files = {
          hidden = true,
          ignored = false,
          args = {
            "--exclude", "node_modules",
            "--exclude", "build",
            "--exclude", "dist",
          },
        },
        grep = {
          hidden = false,
          ignored = false,
        },
        explorer = {
          hidden = true,
          ignored = true,
          win = {
            list = {
              wo = {
                number = true,
                relativenumber = true,
              },
            },
          },
        },
      },
    },
  },
}
