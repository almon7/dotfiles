local api = vim.api
local format_arg = '--format=%x1f%ct%x1f %cn · %h%x1f%D%x1f · %s'
local group = api.nvim_create_augroup('custom-git-log', { clear = true })

local units = {
  { 31536000, 'y' },
  { 2592000, 'mo' },
  { 604800, 'w' },
  { 86400, 'd' },
  { 3600, 'h' },
  { 60, 'm' },
  { 1, 's' },
}

local function compact_age(timestamp, now)
  local elapsed = now - timestamp
  if elapsed < 0 then return '+?  ' end
  for _, unit in ipairs(units) do
    if elapsed >= unit[1] then
      local age = math.floor(elapsed / unit[1]) .. unit[2]
      return #age > 4 and '>99y' or string.format('%-4s', age)
    end
  end
  return '0s  '
end

api.nvim_create_autocmd('User', {
  group = group,
  pattern = 'FugitivePager',
  callback = function()
    -- Fugitive documents this result API in plugin/fugitive.vim.
    local result = vim.fn.FugitiveResult(api.nvim_buf_get_name(0))
    local args = result.args
    if result.exit_status ~= 0 or args[1] ~= 'log' or not vim.tbl_contains(args, format_arg) then return end

    local now = os.time()
    local lines = api.nvim_buf_get_lines(0, 0, -1, false)
    for i, line in ipairs(lines) do
      -- Git separates fields with byte 31 and leaves graph-only rows untouched.
      lines[i] = line:gsub('^(.-)\31(%-?%d+)\31(.-)\31([^\31]*)\31', function(graph, timestamp, commit, refs)
        local labels = refs == '' and '' or ' [' .. refs .. ']'
        return graph .. compact_age(tonumber(timestamp), now) .. commit .. labels
      end, 1)
    end

    vim.bo.modifiable = true
    api.nvim_buf_set_lines(0, 0, -1, false, lines)
    vim.bo.modified = false
    vim.bo.modifiable = false

    -- :setlocal semantics let Neovim restore the window's defaults for other buffers.
    for option, value in pairs { number = false, relativenumber = false, signcolumn = 'no', foldcolumn = '0', wrap = false } do
      api.nvim_set_option_value(option, value, { scope = 'local', win = 0 })
    end
  end,
})

api.nvim_create_user_command(
  'GitLog',
  function(opts) vim.cmd('Git --paginate log --graph --all --date-order --max-count=' .. opts.count .. " --abbrev=7 --decorate=short '" .. format_arg .. "'") end,
  { count = 200, desc = 'Show recent commits as a compact Git graph' }
)
