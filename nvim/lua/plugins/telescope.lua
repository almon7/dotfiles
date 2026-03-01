return {
	{
		'nvim-telescope/telescope.nvim', version = '*',
		dependencies = {
			'nvim-lua/plenary.nvim',
			{ 'nvim-telescope/telescope-fzf-native.nvim', build = 'make' }, -- optional but recommended
		},
		keys = {
			{ '<leader>pf', desc = 'Telescope find files' },
			{ '<C-p>',      desc = 'Telescope git files' },
			{ '<leader>ps', desc = 'Telescope grep string' },
		},
		config = function()
			local builtin = require('telescope.builtin')

			vim.keymap.set('n', '<leader>pf', builtin.find_files, { desc = 'Telescope find files' })
			vim.keymap.set('n', '<C-p>', builtin.git_files, { desc = 'Telescope find git files (not .gitignore)' })
			vim.keymap.set('n', '<leader>ps', function()
				builtin.grep_string({ search = vim.fn.input("Grep > ") });
			end)
			-- Default Options:
			--vim.keymap.set('n', '<leader>ff', builtin.find_files, { desc = 'Telescope find files' })
			--vim.keymap.set('n', '<leader>fg', builtin.live_grep, { desc = 'Telescope live grep' })
			--vim.keymap.set('n', '<leader>fb', builtin.buffers, { desc = 'Telescope buffers' })
			--vim.keymap.set('n', '<leader>fh', builtin.help_tags, { desc = 'Telescope help tags' })
		end,
	},
}
