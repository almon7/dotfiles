return {
	{
		'tpope/vim-fugitive',
		cmd = { 'Git', 'Gdiffsplit', 'Gblame' },
		keys = {
			{ '<leader>gs', desc = 'Git status' },
		},
		config = function()
			vim.keymap.set('n', '<leader>gs', function()
				for _, win in ipairs(vim.api.nvim_list_wins()) do
					local buf = vim.api.nvim_win_get_buf(win)
					if vim.bo[buf].filetype == 'fugitive' then
						vim.api.nvim_win_close(win, false)
						return
					end
				end
				vim.cmd('botright vertical Git')
				vim.cmd('vertical resize 40')
			end)
			vim.keymap.set("n", "<leader>gp", "<cmd>Git push<cr>")
			-- Show all untracked files individually (VS Code style)
			vim.env.GIT_CONFIG_PARAMETERS = "'status.showUntrackedFiles=all'"
		end,
	},
}
