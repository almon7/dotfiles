return {
	{
		'tpope/vim-fugitive',
		cmd = { 'Git', 'Gdiffsplit', 'Gblame' },
		keys = {
			{ '<leader>gs', desc = 'Git status' },
		},
		config = function()
			vim.keymap.set('n', '<leader>gs', vim.cmd.Git)
		end,
	},
}
