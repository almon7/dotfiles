return {
	{
		'tpope/vim-fugitive',
		cmd = { 'Git', 'Gdiffsplit', 'Gblame' },
		keys = {
			{ '<leader>gs', desc = 'Git status' },
		},
		config = function()
			vim.keymap.set('n', '<leader>gs', vim.cmd.Git)
			-- Show all untracked files individually (VS Code style)
			vim.env.GIT_CONFIG_PARAMETERS = "'status.showUntrackedFiles=all'"
		end,
	},
}
