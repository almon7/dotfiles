-- Autosave: on InsertLeave, TextChanged, FocusLost

local autosave_group = vim.api.nvim_create_augroup("AutoSave", { clear = true })

-- Save the current buffer, but only when it's a real, modified file buffer.
local function save_current_buffer()
  local buf = vim.api.nvim_get_current_buf()
  local bo = vim.bo[buf]
  if bo.buftype ~= "" then return end                     -- skip terminals, help, nofile, prompts
  if vim.api.nvim_buf_get_name(buf) == "" then return end -- skip [No Name] buffers
  if not bo.modifiable or bo.readonly then return end
  if not bo.modified then return end                      -- nothing to write
  vim.api.nvim_buf_call(buf, function()
    vim.cmd("silent! write")
  end)
end

-- Autosave on InsertLeave, TextChanged, FocusLost
vim.api.nvim_create_autocmd({ "InsertLeave", "TextChanged", "FocusLost" }, {
  group = autosave_group,
  pattern = "*",
  callback = save_current_buffer,
})

-- Reload buffers changed externally
vim.o.autoread = true
vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter", "CursorHold", "CursorHoldI" }, {
  group = autosave_group,
  pattern = "*",
  callback = function()
    if vim.fn.mode() ~= "c" then
      vim.cmd("silent! checktime")
    end
  end,
})
