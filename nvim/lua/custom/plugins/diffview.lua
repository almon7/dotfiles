vim.pack.add { 'https://github.com/sindrets/diffview.nvim' }

require('diffview').setup {

    -- refined
    enhanced_diff_hl = true,

    -- This is to have changed text in a line green and red
    hooks = {
        diff_buf_win_enter = function(_, _, ctx)
            if ctx.layout_name ~= 'diff2_horizontal' and ctx.layout_name ~= 'diff2_vertical' then return end

            local colour = ctx.symbol == 'a' and 'DiffDelete' or 'DiffAdd'
            vim.opt_local.winhighlight:append {
                DiffText = colour,
                DiffTextAdd = colour,
            }
        end,
    },
}
