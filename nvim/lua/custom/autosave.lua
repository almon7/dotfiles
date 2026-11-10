local api = vim.api
local group = api.nvim_create_augroup('custom-autosave', { clear = true })
local closing = {}
local saving = false -- Write hooks can trigger nested leave or focus events.

-- Leave quit and force-quit handling to Neovim's native autowriteall.
api.nvim_create_autocmd('QuitPre', {
  group = group,
  callback = function()
    local win = api.nvim_get_current_win()
    closing[win] = true
    -- Resume autosave after the quit finishes or is refused.
    vim.schedule(function() closing[win] = nil end)
  end,
})

-- Save a modified file buffer, including one hidden from view.
local function save(buf)
  -- Skip unloaded buffers and files that are unchanged, uneditable or read-only.
  if not api.nvim_buf_is_loaded(buf) then return end
  local options = vim.bo[buf]
  if not options.modified or not options.modifiable or options.readonly or options.buftype ~= '' then return end
  local name = api.nvim_buf_get_name(buf)
  -- Require a file path; writing Git URI buffers could stage changes.
  if name == '' or name:match '^%a[%w+.-]*://' then return end
  -- Prevent write hooks from triggering another autosave.
  saving = true
  -- Run :update in the target buffer; catch failures so other files can still save.
  local ok, err = pcall(api.nvim_buf_call, buf, function() vim.cmd 'silent update' end)
  saving = false -- Allow future autosaves even if writing failed.
  -- Report the failed file without discarding its unsaved text.
  if not ok then vim.notify('Autosave failed for ' .. name .. ': ' .. err, vim.log.levels.ERROR) end
end

api.nvim_create_autocmd({ 'BufLeave', 'WinLeave', 'FocusLost' }, {
  group = group,
  nested = true, -- Preserve formatting and other BufWritePre/BufWritePost hooks.
  callback = function(event)
    if saving or not vim.o.autowriteall or closing[api.nvim_get_current_win()] or vim.v.exiting ~= vim.NIL then return end
    if event.event == 'FocusLost' then
      -- Save hidden files too when focus leaves Neovim.
      for _, buf in ipairs(api.nvim_list_bufs()) do
        save(buf)
      end
    else
      save(event.buf)
    end
  end,
})
