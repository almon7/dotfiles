-- Both colorschemes stay installed and configured (each with its own
-- transparency API). Switch between them live with <leader>uC.
-- The startup default is set at the bottom.
return {
  -- Catppuccin (transparent)
  {
    "catppuccin/nvim",
    opts = {
      transparent_background = true,
    },
  },

  -- Tokyonight (transparent)
  {
    "folke/tokyonight.nvim",
    opts = {
      transparent = true,
      styles = {
        sidebars = "transparent",
        floats = "transparent",
      },
    },
  },

  -- Active colorscheme on startup (change to "tokyonight" to boot into that)
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "catppuccin",
    },
  },
}
