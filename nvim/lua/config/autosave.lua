-- Autosave: on InsertLeave, TextChanged, FocusLost

local autosave_group = vim.api.nvim_create_augroup("AutoSave", { clear = true })

-- Function to save the current buffer if it is modifiable and not readonly
local function save_current_buffer()
  local buf = vim.api.nvim_get_current_buf()
  if vim.bo[buf].modifiable and not vim.bo[buf].readonly then
    vim.api.nvim_buf_call(buf, function()
      vim.cmd("silent! write")
    end)
  end
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

-- Other Settings
--- Diagnostics ---
