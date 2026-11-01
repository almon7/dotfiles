vim.pack.add { 'https://github.com/sindrets/diffview.nvim' }

-- Use window-local matches to darken changed comments and docstrings because diff colours override syntax colours.
local changed_groups = {}
for _, name in ipairs { 'DiffAdd', 'DiffText', 'DiffTextAdd' } do
    changed_groups[vim.api.nvim_get_hl_id_by_name(name)] = true
end

local function add_changed_spans(buf, range, first, last, positions)
    local start_row, start_col, _, end_row, end_col = unpack(range)
    local row = math.max(start_row, first)
    while row <= math.min(end_row, last - 1) do
        local fold_end = vim.fn.foldclosedend(row + 1)
        if fold_end ~= -1 then
            row = fold_end
        else
            local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1]
            local from = row == start_row and start_col or 0
            local to = row == end_row and end_col or #line
            local run
            for col = from, to do
                local changed = col < to and changed_groups[vim.fn.diff_hlID(row + 1, col + 1)]
                if changed and not run then
                    run = col
                elseif not changed and run then
                    positions[#positions + 1] = { row + 1, run + 1, col - run }
                    run = nil
                end
            end
            row = row + 1
        end
    end
end

local function refresh_comments(win)
    for _, match in ipairs(vim.fn.getmatches(win)) do
        if match.group == 'DiffCommentAdd' or match.group == 'DiffCommentDelete' then vim.fn.matchdelete(match.id, win) end
    end
    local colour = vim.w[win].diff_comment_colour
    if not colour or not vim.wo[win].diff then return end
    local buf = vim.api.nvim_win_get_buf(win)
    if buf ~= vim.w[win].diff_comment_buffer then return end
    local parser = vim.treesitter.get_parser(buf)
    if not parser then return end
    local info = vim.fn.getwininfo(win)[1]
    local first, last = info.topline - 1, info.botline
    local positions = {}
    parser:parse { first, last }
    vim.api.nvim_win_call(win, function()
        parser:for_each_tree(function(tree, language_tree)
            local query = vim.treesitter.query.get(language_tree:lang(), 'highlights')
            if not query then return end
            for id, node, metadata in query:iter_captures(tree:root(), buf, first, last) do
                local capture = query.captures[id]
                if capture == 'comment' or capture:match '^comment%.' or capture == 'string.documentation' then
                    add_changed_spans(buf, vim.treesitter.get_range(node, buf, metadata[id]), first, last, positions)
                end
            end
        end)
    end)
    if #positions > 0 then vim.fn.matchaddpos(colour, positions, -1, -1, { window = win }) end
end

local refresh_pending = false
local function schedule_refresh()
    if refresh_pending then return end
    refresh_pending = true
    vim.schedule(function()
        refresh_pending = false
        for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
            if vim.w[win].diff_comment_buffer then refresh_comments(win) end
        end
    end)
end

vim.api.nvim_create_autocmd({ 'DiffUpdated', 'TextChanged', 'TextChangedI', 'WinScrolled', 'BufWinEnter', 'TabEnter', 'OptionSet' }, {
    group = vim.api.nvim_create_augroup('diffview-dark-comments', { clear = true }),
    callback = function(event)
        if event.event == 'OptionSet' and event.match ~= 'diff' then return end
        if event.event == 'TextChanged' or event.event == 'TextChangedI' then
            for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
                if vim.w[win].diff_comment_buffer == event.buf and vim.wo[win].diff then
                    schedule_refresh()
                    return
                end
            end
            return
        end
        schedule_refresh()
    end,
})

require('diffview').setup {

    -- refined
    enhanced_diff_hl = true,

    -- This is to have changed text in a line green and red
    hooks = {
        diff_buf_win_enter = function(buf, _, ctx)
            vim.opt_local.fillchars:append { diff = '·' }
            vim.opt_local.winhighlight:remove 'Comment'
            vim.opt_local.winhighlight:append { ['@string.documentation'] = 'Comment', DiffDelete = 'DiffComment' }
            vim.w.diff_comment_buffer = buf
            vim.w.diff_comment_colour = nil
            schedule_refresh()

            if ctx.layout_name ~= 'diff2_horizontal' and ctx.layout_name ~= 'diff2_vertical' then return end

            vim.w.diff_comment_colour = ctx.symbol == 'a' and 'DiffCommentDelete' or 'DiffCommentAdd'
            local colour = ctx.symbol == 'a' and 'DiffDelete' or 'DiffAdd'
            vim.opt_local.winhighlight:append {
                DiffText = colour,
                DiffTextAdd = colour,
            }
        end,
    },
}
