-- Offline clipboard tests: real buffer positions and paths, no system clipboard access.
-- Run: nvim --headless -u NONE -i NONE -l nvim/test_file_location.lua
local config = vim.fs.dirname(vim.fs.abspath(debug.getinfo(1, "S").source:sub(2)))
local temp = vim.fn.tempname() .. " file location tests"
vim.fn.mkdir(temp, "p")
temp = assert(vim.uv.fs_realpath(temp))
local repo = temp .. "/dotfiles"
vim.fn.mkdir(repo .. "/.git", "p")
vim.fn.mkdir(repo .. "/agents", "p")
vim.fn.writefile({ "first", "\té example", "third" }, repo .. "/agents/AGENTS.md")

local copies, notices = {}, {}
local function copy(lines, regtype)
  copies[#copies + 1] = { lines = vim.deepcopy(lines), regtype = regtype }
end
vim.g.clipboard = {
  name = "Test clipboard",
  copy = { ["+"] = copy, ["*"] = copy },
  paste = {
    ["+"] = function()
      error("Clipboard must remain copy-only")
    end,
    ["*"] = function()
      error("Clipboard must remain copy-only")
    end,
  },
  cache_enabled = 0,
}
vim.notify = function(message, level)
  notices[#notices + 1] = { message = message, level = level }
end
vim.g.mapleader = " "
vim.opt.clipboard = ""
vim.opt.hidden = true
-- The config removes LazyVim's Control navigation mappings on startup.
for _, key in ipairs({ "<C-h>", "<C-j>", "<C-k>", "<C-l>" }) do
  vim.keymap.set("n", key, "<Nop>")
end
dofile(config .. "/lua/config/keymaps.lua")
assert(vim.fn.maparg("<Space>fy", "n", false, true).desc == "Copy file location")
assert(vim.fn.maparg("<Space>fy", "x") == "")
vim.fn.setreg("a", "private yank", "v")
vim.fn.setreg('"', { points_to = "a" })
vim.fn.setreg("0", "previous yank", "v")
local registers = { unnamed = vim.fn.getreginfo('"'), zero = vim.fn.getreginfo("0") }

-- Normal-file copying must not load Diffview or start processes.
package.preload["diffview.lib"] = function()
  error("Unexpected Diffview load")
end
vim.system = function()
  error("Unexpected subprocess")
end
local types = { LOCAL = 1, COMMIT = 2, STAGE = 3, CUSTOM = 4 }
package.loaded["diffview.vcs.rev"] = { RevType = types }

local function buffer(path, buftype)
  local previous = vim.api.nvim_get_current_buf()
  vim.api.nvim_set_current_buf(vim.api.nvim_create_buf(true, false))
  vim.api.nvim_buf_delete(previous, { force = true })
  if path then
    vim.api.nvim_buf_set_name(0, path)
  end
  vim.bo.buftype = buftype or ""
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "first", "\té example", "third" })
  vim.api.nvim_win_set_cursor(0, { 2, 4 }) -- Column 5 in bytes, after a tab and é.
end

local function invoke(expected)
  local before = #copies
  local buf, win = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Space>fy", true, false, true), "xt", false)
  if expected then
    assert(#copies == before + 1, "Expected one clipboard write")
    assert(vim.deep_equal(copies[#copies], { lines = { expected }, regtype = "v" }), vim.inspect(copies[#copies]))
    assert(notices[#notices].message == "Copied " .. expected, vim.inspect(notices[#notices]))
  else
    assert(#copies == before, "Rejected buffer changed the clipboard")
    assert(notices[#notices].level == vim.log.levels.WARN, vim.inspect(notices[#notices]))
  end
  assert(vim.api.nvim_get_current_buf() == buf and vim.api.nvim_get_current_win() == win)
  assert(vim.deep_equal(vim.api.nvim_win_get_cursor(0), cursor))
  assert(vim.deep_equal(vim.api.nvim_buf_get_lines(0, 0, -1, false), lines))
  assert(vim.deep_equal(vim.fn.getreginfo('"'), registers.unnamed))
  assert(vim.deep_equal(vim.fn.getreginfo("0"), registers.zero))
end

local function pane(path, rev)
  return {
    absolute_path = path,
    adapter = { ctx = { toplevel = repo } },
    rev = rev,
    bufnr = vim.api.nvim_get_current_buf(),
  }
end

local function diffview(file)
  package.loaded["diffview.lib"] = {
    get_current_view = function()
      return {
        cur_layout = {
          windows = {
            { id = -1, file = pane(repo .. "/wrong-file", { type = types.LOCAL }) },
            { id = vim.api.nvim_get_current_win(), file = file },
          },
        },
      }
    end,
  }
end

local passed = 0
local function test(name, fn)
  package.loaded["diffview.lib"] = nil
  fn()
  passed = passed + 1
  print("PASS " .. name)
end

local ok, err = xpcall(function()
  test("repository prefix, byte column, and unrelated cwd", function()
    vim.cmd.cd(temp)
    buffer(repo .. "/agents/AGENTS.md")
    invoke("dotfiles/agents/AGENTS.md:2:5")
    assert(package.loaded["diffview.lib"] == nil)
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    invoke("dotfiles/agents/AGENTS.md:1:1")
  end)

  test("named unsaved file with spaces", function()
    buffer(repo .. "/agents/new file.md")
    invoke("dotfiles/agents/new file.md:2:5")
    assert(vim.uv.fs_stat(repo .. "/agents/new file.md") == nil, "Copy saved the buffer")
  end)

  test("worktree folder prefix and .git file", function()
    local worktree = temp .. "/reviews/pr-42"
    vim.fn.mkdir(worktree, "p")
    vim.fn.writefile({ "gitdir: " .. repo .. "/.git/worktrees/pr-42" }, worktree .. "/.git")
    buffer(worktree .. "/example.lua")
    invoke("pr-42/example.lua:2:5")
  end)

  test("config directory symlink, including an unsaved file", function()
    local alias = temp .. "/config-link"
    assert(vim.uv.fs_symlink(repo .. "/agents", alias))
    buffer(alias .. "/AGENTS.md")
    invoke("dotfiles/agents/AGENTS.md:2:5")
    buffer(alias .. "/new alias.md")
    invoke("dotfiles/agents/new alias.md:2:5")
    buffer(alias .. "/new-directory/new alias.md")
    invoke("dotfiles/agents/new-directory/new alias.md:2:5")
  end)

  test("absolute fallback outside Git", function()
    buffer(temp .. "/standalone.md")
    invoke(temp .. "/standalone.md:2:5")
  end)

  test("Diffview rename uses the active historical filename", function()
    buffer("diffview://" .. repo .. "/.git/abcdef/old-name.lua", "nowrite")
    local sha = string.rep("ab", 20)
    diffview(pane(repo .. "/old-name.lua", { type = types.COMMIT, commit = sha }))
    invoke("dotfiles/old-name.lua:2:5 (git commit " .. sha .. ")")
    assert(vim.uv.fs_stat(repo .. "/old-name.lua") == nil)
  end)

  test("Diffview working file and index stages", function()
    buffer("diffview://" .. repo .. "/.git/:0:/new-name.lua", "nowrite")
    diffview(pane(repo .. "/new-name.lua", { type = types.LOCAL }))
    invoke("dotfiles/new-name.lua:2:5")
    for stage, label in pairs({
      [0] = "git index",
      "git index stage 1: base",
      "git index stage 2: ours",
      "git index stage 3: theirs",
    }) do
      diffview(pane(repo .. "/new-name.lua", { type = types.STAGE, stage = stage }))
      invoke("dotfiles/new-name.lua:2:5 (" .. label .. ")")
    end
  end)

  test("navigating to another buffer in a Diffview window", function()
    buffer(repo .. "/diff-file.lua")
    diffview(pane(repo .. "/diff-file.lua", { type = types.LOCAL }))
    buffer(repo .. "/navigation-target.lua")
    invoke("dotfiles/navigation-target.lua:2:5")
  end)

  test("unnamed, terminal, picker, and unresolved virtual buffers", function()
    for _, kind in ipairs({ "", "nofile", "terminal" }) do
      buffer(nil, kind == "terminal" and "" or kind)
      if kind == "terminal" then
        vim.api.nvim_open_term(0, {})
      end
      invoke(nil)
    end
    buffer("diffview://unresolved/file.lua", "")
    invoke(nil)
  end)

  test("Diffview panel, null, binary, and custom revisions", function()
    buffer("diffview://panel", "nofile")
    package.loaded["diffview.lib"] = {
      get_current_view = function()
        return { cur_layout = { windows = {} } }
      end,
    }
    invoke(nil)
    for _, flag in ipairs({ "nulled", "binary" }) do
      local file = pane(repo .. "/example.lua", { type = types.LOCAL })
      file[flag] = true
      diffview(file)
      invoke(nil)
    end
    diffview(pane(repo .. "/example.lua", { type = types.CUSTOM }))
    invoke(nil)
  end)

  test("clipboard errors do not report success", function()
    buffer(repo .. "/error.lua")
    local has = vim.fn.has
    vim.fn.has = function(feature)
      return feature == "clipboard" and 0 or has(feature)
    end
    local before = #copies
    vim.fn.maparg("<Space>fy", "n", false, true).callback()
    assert(#copies == before)
    assert(notices[#notices].level == vim.log.levels.ERROR)
    vim.fn.has = has
    local setreg = vim.fn.setreg
    for _, failure in ipairs({
      function()
        return -1
      end,
      function()
        error("Provider failed")
      end,
    }) do
      vim.fn.setreg = failure
      vim.fn.maparg("<Space>fy", "n", false, true).callback()
      assert(notices[#notices].level == vim.log.levels.ERROR)
    end
    vim.fn.setreg = setreg
  end)
end, debug.traceback)

vim.cmd.cd(config)
vim.fn.delete(temp, "rf")
if not ok then
  error(err)
end
print(("%d file location tests passed"):format(passed))
