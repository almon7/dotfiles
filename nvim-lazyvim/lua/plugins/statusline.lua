return {
  "nvim-lualine/lualine.nvim",
  opts = function(_, opts)
    opts.sections = {
      lualine_a = {},
      lualine_b = {},
      lualine_c = { require("config.statusline").status },
      lualine_x = {},
      lualine_y = {},
      lualine_z = {},
    }
    opts.inactive_sections = vim.deepcopy(opts.sections)
    opts.extensions = {}
    opts.options.component_separators = ""
    opts.options.section_separators = ""

    vim.api.nvim_create_autocmd("DirChanged", {
      group = vim.api.nvim_create_augroup("StatuslineDirectory", { clear = true }),
      callback = function()
        require("lualine").refresh({ place = { "statusline" } })
      end,
    })
  end,
}
