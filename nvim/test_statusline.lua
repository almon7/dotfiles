-- Offline status-bar tests: local Git repositories, no plugins or network required.
-- Run: nvim --headless -u NONE -i NONE -l nvim/test_statusline.lua
local config = vim.fs.dirname(vim.fs.abspath(debug.getinfo(1, "S").source:sub(2)))
local temp = vim.fn.tempname() .. " statusline % tests"
vim.fn.mkdir(temp, "p")
temp = assert(vim.uv.fs_realpath(temp))
local repo, worktree = temp .. "/repo", temp .. "/review"
local system, now = vim.system, vim.uv.now
local clock, refreshes, completed = 0, 0, 0
vim.uv.now = function()
  return clock
end
vim.system = function(args, options, callback)
  return system(args, options, function(result)
    callback(result)
    vim.schedule(function()
      completed = completed + 1
    end)
  end)
end
package.loaded.lualine = {
  refresh = function()
    refreshes = refreshes + 1
  end,
}
local statusline = dofile(config .. "/lua/config/statusline.lua")
package.loaded["config.statusline"] = statusline

local function git(dir, ...)
  local args = {
    "git",
    "-c",
    "user.name=Statusline Test",
    "-c",
    "user.email=statusline@example.test",
    "-c",
    "commit.gpgsign=false",
    "-c",
    "core.hooksPath=/dev/null",
  }
  vim.list_extend(args, { ... })
  local result = system(args, { cwd = dir, text = true }):wait()
  assert(result.code == 0, result.stderr)
  return vim.trim(result.stdout)
end

local function display()
  return vim.api.nvim_eval_statusline(statusline.status(), { maxwidth = 1000 }).str
end

local function expect(dir, suffix)
  vim.cmd.cd(vim.fn.fnameescape(dir))
  clock = clock + 2000
  local before = completed
  display()
  assert(
    vim.wait(5000, function()
      return completed > before
    end, 10),
    "Git status did not finish"
  )
  local expected = vim.fn.fnamemodify(dir, ":~") .. (suffix and "  ·  " .. suffix or "")
  assert(display() == expected, vim.inspect({ expected = expected, actual = display() }))
end

local ok, err = xpcall(function()
  vim.fn.mkdir(repo .. "/sub", "p")
  git(repo, "init", "-b", "main")
  expect(repo, "main") -- Unborn branch.
  vim.fn.writefile({ "ignored" }, repo .. "/.gitignore")
  vim.fn.writefile({ "first" }, repo .. "/tracked")
  git(repo, "add", ".")
  git(repo, "commit", "-m", "Initial")
  expect(repo, "main")
  local unchanged = refreshes
  vim.fn.writefile({ "ignored" }, repo .. "/ignored")
  expect(repo, "main")
  assert(refreshes == unchanged, "Unchanged Git state must not request another redraw")
  vim.fn.writefile({ "untracked" }, repo .. "/new")
  expect(repo, "main *")
  vim.fn.delete(repo .. "/new")
  vim.fn.writefile({ "second" }, repo .. "/tracked")
  expect(repo .. "/sub", "main *") -- Changes outside cwd still count.
  git(repo, "add", "tracked")
  expect(repo, "main *")
  git(repo, "commit", "-m", "Change")
  git(repo, "mv", "tracked", "renamed")
  expect(repo, "main *")
  git(repo, "commit", "-m", "Rename")
  git(repo, "switch", "-c", "feature/100%done")
  expect(repo, "feature/100%done") -- Both the path and branch contain %.
  git(repo, "switch", "main")

  -- Local remote-tracking refs exercise divergence without contacting a server.
  local base = git(repo, "rev-parse", "HEAD")
  git(repo, "remote", "add", "origin", temp .. "/unused-remote")
  git(repo, "update-ref", "refs/remotes/origin/main", base)
  git(repo, "branch", "--set-upstream-to=origin/main", "main")
  expect(repo, "main")
  git(repo, "commit", "--allow-empty", "-m", "Ahead")
  expect(repo, "main  ↑1")
  git(repo, "switch", "-c", "remote-change", base)
  git(repo, "commit", "--allow-empty", "-m", "Behind")
  local upstream = git(repo, "rev-parse", "HEAD")
  git(repo, "update-ref", "refs/remotes/origin/main", upstream)
  git(repo, "switch", "main")
  expect(repo, "main  ↑1  ↓1")
  git(repo, "switch", "-c", "behind-only", base)
  git(repo, "branch", "--set-upstream-to=origin/main", "behind-only")
  expect(repo, "behind-only  ↓1")
  git(repo, "switch", "--detach", upstream)
  expect(repo, upstream:sub(1, 7))
  git(repo, "switch", "main")
  git(repo, "worktree", "add", "-b", "review/pr-42", worktree)
  expect(worktree, "review/pr-42")
  expect(temp)

  -- The current buffer's repository never changes the directory's Git state.
  expect(repo, "main  ↑1  ↓1")
  vim.cmd.edit(vim.fn.fnameescape(worktree .. "/renamed"))
  assert(display():find("main  ↑1  ↓1", 1, true))
  local original = vim.api.nvim_get_current_win()
  vim.cmd.vsplit()
  vim.cmd.lcd(vim.fn.fnameescape(worktree))
  local before = completed
  display()
  assert(vim.wait(5000, function()
    return completed > before
  end, 10))
  assert(display():find("review/pr-42", 1, true))
  vim.api.nvim_set_current_win(original)
  before = completed
  display()
  assert(vim.wait(5000, function()
    return completed > before
  end, 10))
  assert(display():find("main  ↑1  ↓1", 1, true))
  vim.cmd.tabnew()
  vim.cmd.tcd(vim.fn.fnameescape(temp))
  before = completed
  display()
  assert(vim.wait(5000, function()
    return completed > before
  end, 10))
  assert(display() == temp)

  -- Applying the plugin override clears inherited content and keeps the theme/dashboard rules.
  local opts = { options = { theme = "auto", globalstatus = true, disabled_filetypes = { "dashboard" } } }
  dofile(config .. "/lua/plugins/statusline.lua").opts(nil, opts)
  assert(opts.options.theme == "auto" and opts.options.globalstatus)
  assert(opts.options.disabled_filetypes[1] == "dashboard" and #opts.extensions == 0)
  for section, components in pairs(opts.sections) do
    assert(#components == (section == "lualine_c" and 1 or 0))
  end
  before = refreshes
  vim.cmd.cd(vim.fn.fnameescape(repo))
  assert(refreshes > before, "Directory changes must request an immediate redraw")

  -- Hold completions to test throttling, rapid switches, failures and obsolete results.
  local calls = {}
  vim.system = function(args, options, callback)
    assert(args[1] == "git" and options.timeout == 5000)
    calls[#calls + 1] = { cwd = options.cwd, done = callback }
  end
  statusline = dofile(config .. "/lua/config/statusline.lua")
  assert(display() == repo)
  clock = clock + 10000
  display()
  assert(#calls == 1, "A pending query must not be duplicated")
  vim.cmd.cd(vim.fn.fnameescape(worktree))
  assert(display() == worktree and #calls == 2)
  vim.cmd.cd(vim.fn.fnameescape(repo))
  assert(display() == repo and #calls == 2)
  local function complete(index, code, output)
    calls[index].done({ code = code, stdout = output or "" })
    vim.wait(20, function()
      return false
    end, 5)
  end
  complete(1, 0, "# branch.head obsolete\n")
  complete(2, 0, "# branch.head wrong-directory\n")
  assert(display() == repo and #calls == 3, "Obsolete results must be discarded")
  complete(3, 0, "# branch.head current\n")
  assert(display() == repo .. "  ·  current")
  clock = clock + 1999
  display()
  assert(#calls == 3, "Git queries must be throttled")
  clock = clock + 1
  display()
  assert(#calls == 4)
  complete(4, 124)
  assert(display() == repo, "Timeouts must clear stale Git information")
  clock = clock + 2000
  display()
  complete(5, 0, "# branch.head current\n")
  vim.system = function()
    error("Git cannot start")
  end
  clock = clock + 2000
  assert(display() == repo, "Spawn failures must clear stale Git information")
end, debug.traceback)

vim.system, vim.uv.now = system, now
vim.cmd.cd(config)
vim.fn.delete(temp, "rf")
assert(ok, err)
print("Statusline tests passed")
