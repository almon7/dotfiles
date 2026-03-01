return {
	{
		'lewis6991/gitsigns.nvim',
		event = { 'BufReadPre', 'BufNewFile' },
		opts = {
            signs = {
                add          = { text = '┃' },
                change       = { text = '┃' },
                delete       = { text = '_' },
                topdelete    = { text = '‾' },
                changedelete = { text = '~' },
                untracked    = { text = '┆' },
            },
                signs_staged = {
                add          = { text = '┃' },
                change       = { text = '┃' },
                delete       = { text = '_' },
                topdelete    = { text = '‾' },
                changedelete = { text = '~' },
                untracked    = { text = '┆' },
            },
                signs_staged_enable = true,
                signcolumn = true,  -- Toggle with `:Gitsigns toggle_signs`
                numhl      = false, -- Toggle with `:Gitsigns toggle_numhl`
                linehl     = false, -- Toggle with `:Gitsigns toggle_linehl`
                word_diff  = false, -- Toggle with `:Gitsigns toggle_word_diff`
                watch_gitdir = {
                follow_files = true
            },
                auto_attach = true,
                attach_to_untracked = false,
                current_line_blame = false, -- Toggle with `:Gitsigns toggle_current_line_blame`
                current_line_blame_opts = {
                virt_text = true,
                virt_text_pos = 'eol', -- 'eol' | 'overlay' | 'right_align'
                delay = 1000,
                ignore_whitespace = false,
                virt_text_priority = 100,
                use_focus = true,
            },
                current_line_blame_formatter = '<author>, <author_time:%R> - <summary>',
                sign_priority = 6,
                update_debounce = 100,
                status_formatter = nil, -- Use default
                max_file_length = 40000, -- Disable if file is longer than this (in lines)
                preview_config = {
                -- Options passed to nvim_open_win
                style = 'minimal',
                relative = 'cursor',
                row = 0,
                col = 1
            },

			-- Show number of changed lines in the statusline via vim.b.gitsigns_status
			current_line_blame = false,
			on_attach = function(bufnr)
                local gitsigns = require('gitsigns')

                local function map(mode, l, r, opts)
                    opts = opts or {}
                    opts.buffer = bufnr
                    vim.keymap.set(mode, l, r, opts)
                end

                -- Navigation
                -- Jump to next hunk (or next diff line in diff mode)
                map('n', ']c', function()
                    if vim.wo.diff then
                    vim.cmd.normal({']c', bang = true})
                    else
                    gitsigns.nav_hunk('next')
                    end
                end)

                -- Jump to previous hunk (or previous diff line in diff mode)
                map('n', '[c', function()
                    if vim.wo.diff then
                    vim.cmd.normal({'[c', bang = true})
                    else
                    gitsigns.nav_hunk('prev')
                    end
                end)

                -- Actions
                map('n', '<leader>hs', gitsigns.stage_hunk)           -- Stage hunk under cursor
                map('n', '<leader>hr', gitsigns.reset_hunk)           -- Reset hunk under cursor

                -- Stage selected lines (visual mode)
                map('v', '<leader>hs', function()
                    gitsigns.stage_hunk({ vim.fn.line('.'), vim.fn.line('v') })
                end)

                -- Reset selected lines (visual mode)
                map('v', '<leader>hr', function()
                    gitsigns.reset_hunk({ vim.fn.line('.'), vim.fn.line('v') })
                end)

                map('n', '<leader>hS', gitsigns.stage_buffer)         -- Stage entire buffer
                map('n', '<leader>hR', gitsigns.reset_buffer)         -- Reset entire buffer
                map('n', '<leader>hp', gitsigns.preview_hunk)         -- Preview hunk in floating window
                map('n', '<leader>hi', gitsigns.preview_hunk_inline)  -- Preview hunk inline

                -- Show full git blame for current line
                map('n', '<leader>hb', function()
                    gitsigns.blame_line({ full = true })
                end)

                map('n', '<leader>hd', gitsigns.diffthis)             -- Diff current file against index

                -- Diff current file against last commit
                map('n', '<leader>hD', function()
                    gitsigns.diffthis('~')
                end)

                map('n', '<leader>hQ', function() gitsigns.setqflist('all') end) -- Send all hunks to quickfix list
                map('n', '<leader>hq', gitsigns.setqflist)                       -- Send buffer hunks to quickfix list

                -- Toggles
                map('n', '<leader>tb', gitsigns.toggle_current_line_blame) -- Toggle inline git blame
                map('n', '<leader>tw', gitsigns.toggle_word_diff)          -- Toggle word-level diff highlights

                -- Text object: select hunk (use in operator-pending and visual mode)
                map({'o', 'x'}, 'ih', gitsigns.select_hunk)
                end
		},
	},
}
