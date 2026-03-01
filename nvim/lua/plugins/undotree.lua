return {
	{
		"jiaoshijie/undotree",
		opts = {
			-- your options
		},
		keys = { -- load the plugin only when using its keybinding:
			{ "<leader>u", desc = "Toggle UndoTree" },
		},
		config = function()
			vim.keymap.set('n', '<leader>u', require('undotree').toggle, { noremap = true, silent = true })
		end,
	},
}
