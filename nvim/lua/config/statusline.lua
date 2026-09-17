local M = {}
local current
local pending = {}

local function git_status(output)
  local branch = output:match("# branch.head ([^\n]+)")
  if not branch then
    return ""
  end
  if branch == "(detached)" then
    branch = (output:match("# branch.oid (%x+)") or ""):sub(1, 7)
  end
  if output:find("\n[12u?] ") then
    branch = branch .. " *"
  end
  local ahead, behind = output:match("# branch.ab %+(%d+) %-(%d+)")
  if ahead and tonumber(ahead) > 0 then
    branch = branch .. "  ↑" .. ahead
  end
  if behind and tonumber(behind) > 0 then
    branch = branch .. "  ↓" .. behind
  end
  return branch
end

function M.status()
  local cwd = vim.fn.getcwd()
  if not current or current.cwd ~= cwd then
    current = { cwd = cwd, git = "", checked = -math.huge }
  end
  local state = current
  local now = vim.uv.now()
  if not pending[cwd] and now - state.checked >= 2000 then
    pending[cwd] = true
    state.checked = now
    local ok = pcall(
      vim.system,
      { "git", "--no-optional-locks", "status", "--porcelain=v2", "--branch", "--untracked-files=normal" },
      { cwd = cwd, text = true, timeout = 5000 },
      vim.schedule_wrap(function(result)
        pending[cwd] = nil
        -- A result from a directory we left must not overwrite the active bar.
        if current ~= state then
          return
        end
        local git = result.code == 0 and git_status(result.stdout) or ""
        if state.git ~= git then
          state.git = git
          require("lualine").refresh({ place = { "statusline" } })
        end
      end)
    )
    if not ok then
      pending[cwd] = nil
      state.git = ""
    end
  end
  local text = vim.fn.fnamemodify(cwd, ":~")
  if state.git ~= "" then
    text = text .. "  ·  " .. state.git
  end
  return (text:gsub("%%", "%%%%"))
end

return M
