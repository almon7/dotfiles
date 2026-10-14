-- Headless entry point: no user init, plugins or autosave are loaded by nvim -l.
local root = vim.fs.dirname(debug.getinfo(1, "S").source:sub(2))
vim.opt.rtp:prepend(root)
local ok, err = pcall(function()
  require("config.review_session").run(arg[1], arg[2])
end)
if not ok then
  io.stderr:write(tostring(err) .. "\n")
  vim.cmd("cquit 1")
end
