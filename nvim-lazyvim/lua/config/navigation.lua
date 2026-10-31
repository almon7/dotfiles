local M = {}

-- Terminal expression mappings run under text-lock. Schedule navigation and
-- consume the key instead of forwarding Vim's terminal escape sequence to a job.
function M.terminal(command)
  return function()
    vim.schedule(function()
      vim.cmd(command)
    end)
    return ""
  end
end

return M
