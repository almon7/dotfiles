require'nvim-treesitter'.setup {
	-- Empty for now
}

-- Await async install
require'nvim-treesitter'.install {
	"vimdoc", "python", "haskell", "lua", "html", "css", "javascript"
}:wait(300000)

vim.api.nvim_create_autocmd('FileType', {
	pattern = {
		"help", "python", "haskell", "lua", "html", "css", "javascript"
	},
	-- Syntax Highlighting
	callback = function() 
		vim.treesitter.start()

		-- Folding
		--vim.wo[0][0].foldexpr = 'v:lua.vim.treesitter.foldexpr()'
		--vim.wo[0][0].foldmethod = 'expr'

		-- Indentation (Experimental)
		vim.bo.indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
	end,
})

