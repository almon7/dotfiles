-- Normal .1729-px/app/common/athena_chat.py Git ce1bdbf (detached) Diff ~4 W4 47:1
-- File type, size and LSP counts are omitted.
local M = {}
local statusline = require 'mini.statusline'

local function escape(text) return (text:gsub('%%', '%%%%')) end

-- Show worktree/path (worktree/…/filename below 120 columns); use normal filenames for non-Git/special buffers.
-- Keep unsaved [+] and read-only [RO] markers.
local function filename()
  local git = vim.b.gitsigns_status_dict
  local name = vim.api.nvim_buf_get_name(0)
  local relative = git and git.root and vim.fs.relpath(git.root, name)
  if vim.bo.buftype ~= '' or not relative then return statusline.section_filename { trunc_width = 120 } end

  if statusline.is_truncated(120) and relative:find '/' then relative = '…/' .. vim.fs.basename(relative) end
  return escape(vim.fs.basename(git.root) .. '/' .. relative) .. '%m%r'
end

-- Show the branch or a commit labelled (detached); hide Git below 100 columns.
local function git_head()
  if statusline.is_truncated(100) then return '' end
  local git = vim.b.gitsigns_status_dict
  local head = git and git.head or vim.b.gitsigns_head
  if not head or head == '' then return '' end

  if git and git.gitdir and vim.fn.exists '*FugitiveHead' == 1 then
    local branch = vim.fn.FugitiveHead(0, git.gitdir)
    local commit = branch == '' and vim.fn.FugitiveHead(7, git.gitdir) or ''
    if branch ~= '' then
      head = branch
    elseif commit ~= '' then
      head = commit .. ' (detached)'
    end
  end
  return 'Git ' .. escape(head)
end

-- Show non-zero errors (E) and warnings (W); Space t d also hides these counts.
local function diagnostics()
  if not vim.diagnostic.is_enabled { bufnr = 0 } then return '' end
  local counts = vim.diagnostic.count(0)
  local parts = {}
  for _, level in ipairs { { vim.diagnostic.severity.ERROR, 'E' }, { vim.diagnostic.severity.WARN, 'W' } } do
    if (counts[level[1]] or 0) > 0 then parts[#parts + 1] = level[2] .. counts[level[1]] end
  end
  return table.concat(parts, ' ')
end

-- Show encoding and line endings only when different from UTF-8 and Unix/LF.
local function file_format()
  if vim.bo.buftype ~= '' then return '' end
  local encoding = vim.bo.fileencoding ~= '' and vim.bo.fileencoding or vim.o.encoding
  local parts = {}
  if encoding ~= 'utf-8' then parts[#parts + 1] = encoding end
  if vim.bo.fileformat ~= 'unix' then parts[#parts + 1] = '[' .. vim.bo.fileformat .. ']' end
  return table.concat(parts, ' ')
end

-- Check from the repository root with Mini, Gitsigns and Fugitive installed:
-- nvim --headless -u NONE -i NONE -l nvim/tests/statusline.lua
function M.setup()
  statusline.setup {
    use_icons = vim.g.have_nerd_font,
    content = {
      active = function()
        -- Abbreviate the mode below 120 columns.
        local mode, mode_hl = statusline.section_mode { trunc_width = 120 }
        -- Non-zero buffer changes against Git's staging area, not the PR total; hide below 120 columns.
        local diff = ''
        if vim.b.gitsigns_status and vim.b.gitsigns_status ~= '' then
          diff = statusline.section_diff { trunc_width = 120, icon = 'Diff' }
        end
        local info = { git_head(), diff, diagnostics() }
        local groups = {
          { hl = mode_hl, strings = { mode } },
          { hl = 'MiniStatuslineFilename', strings = { filename() } },
          { hl = 'MiniStatuslineDevinfo', strings = info },
          { hl = 'MiniStatuslineFileinfo', strings = { file_format() } },
          -- Show search counts while highlighting is active at 75+ columns; cursor position is line:column.
          { hl = mode_hl, strings = { statusline.section_searchcount { trunc_width = 75 }, '%2l:%-2v' } },
        }
        -- Measure without padding or truncation, dropping diff then Git before shortening the filename.
        local width = vim.o.laststatus == 3 and vim.o.columns or vim.api.nvim_win_get_width(0)
        for _, index in ipairs { 2, 1 } do
          if
            vim.api.nvim_eval_statusline(statusline.combine_groups(groups), { maxwidth = width + 1 }).width <= width
          then
            break
          end
          info[index] = ''
        end
        table.insert(groups, 2, '%<')
        table.insert(groups, 4, '%=')
        return statusline.combine_groups(groups)
      end,
      -- Inactive windows show only the filename and unsaved/read-only markers.
      inactive = function() return '%#MiniStatuslineInactive# ' .. filename() .. '%=' end,
    },
  }
end

return M
