return {
  "lukas-reineke/virt-column.nvim",
  lazy = false,
  opts = {
    char = "│",
    highlight = "VirtColumnSubtle",
  },
  config = function(_, opts)
    require("virt-column").setup(opts)

    local function set_subtle_highlight()
      local cursor_line = vim.api.nvim_get_hl(0, { name = "CursorLine", link = false })
      local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
      local background = cursor_line.bg or normal.bg

      if background then
        vim.api.nvim_set_hl(0, "VirtColumnSubtle", { fg = background })
      else
        vim.api.nvim_set_hl(0, "VirtColumnSubtle", { link = "NonText" })
      end
    end

    vim.api.nvim_create_autocmd("ColorScheme", {
      group = vim.api.nvim_create_augroup("VirtColumnSubtle", { clear = true }),
      callback = set_subtle_highlight,
    })
    set_subtle_highlight()
  end,
}
