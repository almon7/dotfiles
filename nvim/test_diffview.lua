-- Offline integration tests: real Git repositories, mocked GitHub and tmux.
-- Run: nvim --headless -u NONE -i NONE -l nvim/test_diffview.lua
local config = vim.fs.dirname(vim.fs.abspath(debug.getinfo(1, "S").source:sub(2)))
vim.opt.rtp:prepend(config)
local temp = vim.fn.tempname() .. " diffview tests"
vim.fn.mkdir(temp, "p")
temp = assert(vim.uv.fs_realpath(temp))
vim.env.NVIM_LOG_FILE = temp .. "/nvim.log"
local system = vim.system
local expand = vim.fn.expand
local executable = vim.fn.executable
local exepath = vim.fn.exepath
local env = { GIT_CONFIG_GLOBAL = "/dev/null", GIT_CONFIG_SYSTEM = "/dev/null", GIT_TERMINAL_PROMPT = "0" }
local metadata, reply, gh_error, redirect, missing_gh, missing_hunk, missing_tmux, tmux_error, redirect_pane
local opened, histories, messages, launches, calls, prompts = {}, {}, {}, {}, {}, {}
local listed_prs, selections, selection = {}, {}, "manual"
local viewer, destination = "Diffview", "Right-hand tmux pane"
local choices = {}
local hunk_path = "/tools with spaces/hunk"
local ui_pending = 0
local worktrees = {}
local passed = 0

local function command(cwd, args)
  local result = system(args, { cwd = cwd, text = true, env = env }):wait()
  assert(result.code == 0, table.concat(args, " ") .. "\n" .. result.stderr)
  return vim.trim(result.stdout)
end

local function git(cwd, ...)
  return command(cwd, vim.list_extend({ "git" }, { ... }))
end

local function write(path, text)
  vim.fn.writefile({ text }, path)
end

local function commit(repo, file, text)
  write(repo .. "/" .. file, text)
  git(repo, "add", "--", file)
  git(
    repo,
    "-c",
    "user.name=Test",
    "-c",
    "user.email=test@example.com",
    "-c",
    "commit.gpgsign=false",
    "commit",
    "-m",
    text
  )
  return git(repo, "rev-parse", "HEAD")
end

local function fixture(name)
  local seed, bare, checkout = temp .. "/" .. name .. " seed", temp .. "/" .. name .. ".git", temp .. "/" .. name
  git(temp, "init", "-b", "develop", seed)
  local base = commit(seed, "example.txt", "base")
  git(seed, "switch", "-c", "feature")
  local head = commit(seed, "example.txt", "PR change")
  git(seed, "switch", "develop")
  local target = commit(seed, "unrelated.txt", "target advanced")
  git(temp, "clone", "--bare", seed, bare)
  git(bare, "update-ref", "refs/pull/42/head", head)
  git(bare, "update-ref", "-d", "refs/heads/feature") -- PR is only available through refs/pull, as with forks.
  git(temp, "clone", bare, checkout)
  local url = "https://github.com/acme/" .. name .. ".git"
  git(checkout, "remote", "set-url", "origin", url)
  git(checkout, "config", "url." .. bare .. ".insteadOf", url)
  return {
    seed = seed,
    bare = bare,
    repo = checkout,
    base = base,
    head = head,
    pr = {
      number = 42,
      url = "https://github.com/acme/" .. name .. "/pull/42",
      baseRefName = "develop",
      baseRefOid = target,
      headRefOid = head,
    },
  }
end

vim.fn.expand = function(value, ...)
  return value == "~/reviews" and (temp .. "/reviews") or expand(value, ...)
end
vim.fn.executable = function(value)
  if value == "gh" then
    return missing_gh and 0 or 1
  end
  if value == "tmux" then
    return missing_tmux and 0 or 1
  end
  return executable(value)
end
vim.fn.exepath = function(value)
  if value == "hunk" then
    return missing_hunk and "" or hunk_path
  end
  return exepath(value)
end
vim.notify = function(message, level, opts)
  if opts and opts.title == "Git view" then
    messages[#messages + 1] = { text = message, level = level }
  end
end
local function respond(callback, value)
  ui_pending = ui_pending + 1
  callback(value)
  vim.schedule(function()
    ui_pending = ui_pending - 1
  end)
end
vim.ui.input = function(opts, callback)
  prompts[#prompts + 1] = opts
  respond(callback, reply)
end
vim.ui.select = function(items, opts, callback)
  choices[#choices + 1] = { items = items, opts = opts }
  if opts.prompt == "PR viewer: " then
    respond(callback, viewer)
    return
  end
  if opts.prompt == "Open Hunk in: " then
    respond(callback, destination)
    return
  end
  selections[#selections + 1] = { items = items, opts = opts }
  respond(callback, selection == "manual" and items[#items] or items[selection])
end
package.loaded.diffview = {
  open = function(args)
    opened[#opened + 1] = args
  end,
  file_history = function(_, args)
    histories[#histories + 1] = args
  end,
}
vim.system = function(args, opts, callback)
  calls[#calls + 1] = { args = vim.deepcopy(args), cwd = opts.cwd }
  if args[1] == "gh" or args[1] == "tmux" then
    local result = { code = 0, stdout = "", stderr = "" }
    if args[1] == "gh" then
      result = {
        code = gh_error and 1 or 0,
        stderr = gh_error or "",
        stdout = vim.json.encode(args[3] == "list" and listed_prs or metadata),
      }
    elseif args[2] == "display-message" then
      result.stdout = "$9"
    end
    if args[1] == "tmux" and tmux_error and tmux_error.command == args[2] then
      result.code, result.stderr = 1, tmux_error.message
    end
    vim.schedule(function()
      if redirect then
        vim.cmd.cd(redirect)
        redirect = nil
      end
      if redirect_pane then
        vim.env.TMUX_PANE = redirect_pane
        redirect_pane = nil
      end
      callback(result)
      if args[1] == "tmux" and result.code == 0 and (args[2] == "new-window" or args[2] == "split-window") then
        -- run() schedules its continuation; record completion after that continuation.
        vim.schedule(function()
          launches[#launches + 1] = args
        end)
      end
    end)
    return {}
  end
  opts.env = env
  return system(args, opts, callback)
end

local review = require("config.diffview")
local function invoke(fn, expected)
  local old_opened, old_launches, old_messages = #opened, #launches, #messages
  fn()
  local done = vim.wait(5000, function()
    if #opened > old_opened or #launches > old_launches then
      return true
    end
    for index = old_messages + 1, #messages do
      if messages[index].level >= vim.log.levels.WARN then
        return true
      end
    end
    return false
  end, 5)
  assert(done, "Operation timed out")
  local errors = {}
  for index = old_messages + 1, #messages do
    if messages[index].level >= vim.log.levels.WARN then
      errors[#errors + 1] = messages[index].text
    end
  end
  if expected then
    assert(
      table.concat(errors, "\n"):find(expected, 1, true),
      "Expected " .. expected .. "; got " .. table.concat(errors, "\n")
    )
    assert(#opened == old_opened and #launches == old_launches, "Failed operation opened a review")
  else
    assert(#errors == 0, table.concat(errors, "\n"))
  end
end

local function test(name, fn)
  fn()
  passed = passed + 1
  print("PASS " .. name)
end

local ok, err = xpcall(function()
  local a, b = fixture("api"), fixture("web")
  vim.cmd.cd(a.repo)
  metadata, reply = a.pr, "42"
  listed_prs = {
    {
      number = 43,
      url = a.pr.url:gsub("42$", "43"),
      title = "Newer change",
      author = { login = "bob" },
      isDraft = true,
    },
    { number = 42, url = a.pr.url, title = "PR change", author = { login = "alice" }, isDraft = false },
  }
  test("picker lists newest open PRs and reviews the selected URL without a prompt", function()
    selection = 2
    local before, before_prompts = #calls, #prompts
    invoke(review.pr)
    assert(vim.deep_equal(calls[before + 1].args, {
      "gh",
      "pr",
      "list",
      "--state",
      "open",
      "--limit",
      "50",
      "--search",
      "sort:created-desc",
      "--json",
      "number,title,url,author,isDraft",
    }))
    local picker = selections[#selections]
    assert(#picker.items == 3)
    assert(picker.opts.format_item(picker.items[1]) == "#43 Newer change — @bob [draft]")
    assert(picker.opts.format_item(picker.items[2]) == "#42 PR change — @alice")
    assert(picker.opts.format_item(picker.items[3]) == "Enter PR number or URL…")
    assert(
      picker.opts.format_item({ number = 1, title = "Deleted author", author = vim.NIL })
        == "#1 Deleted author — @unknown"
    )
    assert(calls[before + 2].args[3] == "view" and calls[before + 2].args[4] == a.pr.url)
    assert(#prompts == before_prompts)
    assert(vim.deep_equal(choices[#choices].items, { "Diffview", "Hunk" }))
    assert(opened[#opened][2] == a.base .. ".." .. a.head)
    selection = "manual"
  end)
  test("empty PR list keeps manual entry available", function()
    local previous, before_messages = listed_prs, #messages
    listed_prs = {}
    reply = "#42"
    invoke(review.pr)
    assert(#selections[#selections].items == 1)
    assert(messages[before_messages + 1].text == "No open PRs.")
    assert(opened[#opened][2] == a.base .. ".." .. a.head)
    listed_prs, reply = previous, "42"
  end)
  test("published PR uses merge base and fork ref, preserving dirty checkout", function()
    write(a.repo .. "/example.txt", "local edit")
    local status = git(a.repo, "status", "--porcelain")
    local head = git(a.repo, "rev-parse", "HEAD")
    invoke(review.pr)
    assert(opened[#opened][1] == "-C" .. a.repo)
    assert(opened[#opened][2] == a.base .. ".." .. a.head)
    assert(#opened[#opened] == 2, "Published PR diffs must not substitute local files")
    assert(git(a.repo, "status", "--porcelain") == status)
    assert(git(a.repo, "rev-parse", "HEAD") == head)
    assert(git(a.repo, "symbolic-ref", "--short", "HEAD") == "develop")
  end)
  test("asynchronous PR keeps its original repository after switching cwd", function()
    selection = 2
    local before = #calls
    redirect = b.repo
    invoke(review.pr)
    assert(opened[#opened][1] == "-C" .. a.repo)
    for index = before + 1, #calls do
      assert(calls[index].cwd == a.repo)
    end
    vim.cmd.cd(a.repo)
    selection = "manual"
  end)
  test("SSH remote identity works with offline URL rewriting", function()
    local ssh = "git@github.com:acme/api.git"
    git(a.repo, "remote", "set-url", "origin", ssh)
    git(a.repo, "config", "url." .. a.bare .. ".insteadOf", ssh)
    invoke(review.pr)
    assert(opened[#opened][2] == a.base .. ".." .. a.head)
    git(a.repo, "remote", "set-url", "origin", "https://github.com/acme/api.git")
    git(a.repo, "config", "url." .. a.bare .. ".insteadOf", "https://github.com/acme/api.git")
  end)
  test("branch comparison fetches a newer non-main target", function()
    local branch = fixture("branch")
    vim.cmd.cd(branch.repo)
    metadata, reply = branch.pr, "origin/develop"
    local target = commit(branch.repo, "upstream.txt", "upstream advanced")
    git(branch.repo, "push", branch.bare, "HEAD:refs/heads/develop")
    git(branch.repo, "switch", "-c", "local-feature")
    local head = commit(branch.repo, "local.txt", "local feature")
    assert(git(branch.repo, "rev-parse", "origin/develop") == branch.pr.baseRefOid)
    invoke(review.branch)
    assert(opened[#opened][2] == target .. ".." .. head)
    assert(opened[#opened][3] == "--imply-local", "Branch reviews need real files for LSP navigation")
    vim.cmd.cd(a.repo)
    metadata = a.pr
  end)
  test("unconfigured PR remote keeps the branch base prompt available", function()
    metadata, reply = b.pr, "develop"
    local before = #prompts
    invoke(review.branch)
    assert(#prompts == before + 1 and prompts[#prompts].default == "origin/develop")
    assert(opened[#opened][2] == a.pr.baseRefOid .. ".." .. a.pr.baseRefOid)
    metadata, reply = a.pr, "42"
  end)
  test("local, staged, and history commands preserve paths with spaces", function()
    review.open()
    assert(opened[#opened][1] == "-C" .. a.repo and #opened[#opened] == 1)
    review.open(true)
    assert(opened[#opened][2] == "--cached")
    vim.cmd.edit(vim.fn.fnameescape(a.repo .. "/example.txt"))
    review.history(true)
    assert(histories[#histories][2] == a.repo .. "/example.txt")
    review.history()
    assert(#histories[#histories] == 1)
    vim.cmd.enew()
  end)
  test("PR URL must match current repository", function()
    metadata, reply = b.pr, b.pr.url
    invoke(review.pr, "does not match a remote")
    metadata, reply = a.pr, "42"
  end)
  test("authentication errors do not open a diff", function()
    local before, before_selections = #calls, #selections
    gh_error = "Authenticate with gh auth login"
    invoke(review.pr, "gh auth login")
    assert(#selections == before_selections and #calls == before + 1)
    gh_error = nil
  end)
  test("invalid manual input stops after listing PRs", function()
    reply = "42; touch injected"
    local before = #calls
    invoke(review.pr, "Enter a PR number")
    assert(#calls == before + 1 and calls[#calls].args[3] == "list")
    reply = "42"
  end)
  test("picker and manual prompt cancellation do not fetch or open reviews", function()
    for _, manual in ipairs({ false, true }) do
      selection, reply = manual and "manual" or nil, nil
      local before, before_selections = #calls, #selections
      local before_opened, before_launches, before_messages = #opened, #launches, #messages
      review.pr()
      assert(vim.wait(1000, function()
        return #selections > before_selections and ui_pending == 0
      end, 5))
      assert(#calls == before + 1 and calls[#calls].args[3] == "list")
      assert(#opened == before_opened and #launches == before_launches and #messages == before_messages)
    end
    selection, reply = "manual", "42"
  end)
  test("missing gh and tmux context report the required tool", function()
    missing_gh = true
    invoke(review.pr, "GitHub CLI is missing")
    missing_gh = false
    vim.env.TMUX = nil
    invoke(function()
      review.pr(true)
    end, "inside tmux")
  end)
  test("PR updated during fetch is not displayed as the old PR", function()
    metadata = vim.deepcopy(a.pr)
    metadata.headRefOid = a.base
    invoke(review.pr, "changed while fetching")
    metadata = a.pr
  end)
  test("failed PR fetch does not fall back to local files", function()
    git(a.bare, "update-ref", "-d", "refs/pull/42/head")
    invoke(review.pr, "remote ref")
    git(a.bare, "update-ref", "refs/pull/42/head", a.head)
  end)
  test("Diffview remains available without Hunk or tmux", function()
    vim.env.TMUX, vim.env.TMUX_PANE = nil, nil
    missing_hunk, missing_tmux = true, true
    local before = #choices
    invoke(review.pr)
    assert(#choices == before + 2, "Diffview should only ask for the PR and viewer")
    assert(opened[#opened][2] == a.base .. ".." .. a.head)
    missing_hunk, missing_tmux = false, false
  end)
  test("Hunk opens exact published revisions in the original tmux pane or session", function()
    viewer = "Hunk"
    local status = git(a.repo, "status", "--porcelain")
    local head = git(a.repo, "rev-parse", "HEAD")
    local trees = git(a.repo, "worktree", "list", "--porcelain")
    for _, place in ipairs({ "Right-hand tmux pane", "New tmux window" }) do
      destination = place
      vim.env.TMUX, vim.env.TMUX_PANE = "/tmp/test-tmux,123,0", "%1"
      redirect, redirect_pane = b.repo, "%999"
      local before, before_opened = #calls, #opened
      invoke(review.pr)
      assert(#opened == before_opened, "Hunk must not open Diffview")
      assert(vim.deep_equal(choices[#choices].items, { "Right-hand tmux pane", "New tmux window" }))
      local expected = place == "Right-hand tmux pane" and { "tmux", "split-window", "-h", "-l", "50%", "-t", "%1" }
        or { "tmux", "new-window", "-t", "$9:", "-n", "api/pr-42 — Hunk" }
      vim.list_extend(expected, { "-c", a.repo, "--", hunk_path, "diff", a.base .. ".." .. a.head })
      assert(vim.deep_equal(launches[#launches], expected))
      for index = before + 1, #calls do
        assert(calls[index].cwd == a.repo)
        if calls[index].args[2] == "display-message" then
          assert(calls[index].args[5] == "%1")
        end
      end
      assert(git(a.repo, "status", "--porcelain") == status)
      assert(git(a.repo, "rev-parse", "HEAD") == head)
      assert(git(a.repo, "symbolic-ref", "--short", "HEAD") == "develop")
      assert(git(a.repo, "worktree", "list", "--porcelain") == trees)
      vim.cmd.cd(a.repo)
    end
    viewer, destination = "Diffview", "Right-hand tmux pane"
  end)
  test("viewer and Hunk destination cancellation do not fetch or launch", function()
    for _, cancel_destination in ipairs({ false, true }) do
      viewer, destination = cancel_destination and "Hunk" or nil, nil
      local before, before_choices = #calls, #choices
      local before_opened, before_launches, before_messages = #opened, #launches, #messages
      review.pr()
      local expected_choices = cancel_destination and 3 or 2
      assert(vim.wait(1000, function()
        return #choices == before_choices + expected_choices and ui_pending == 0
      end, 5))
      assert(#calls == before + 1 and calls[#calls].args[3] == "list")
      assert(#opened == before_opened and #launches == before_launches and #messages == before_messages)
    end
    viewer, destination = "Diffview", "Right-hand tmux pane"
  end)
  test("Hunk prerequisites fail before fetching", function()
    viewer = "Hunk"
    for _, missing in ipairs({ "hunk", "tmux", "session", "pane" }) do
      vim.env.TMUX = missing ~= "session" and "/tmp/test-tmux,123,0" or nil
      vim.env.TMUX_PANE = missing ~= "pane" and "%1" or nil
      missing_hunk, missing_tmux = missing == "hunk", missing == "tmux"
      local before = #calls
      invoke(review.pr, missing == "hunk" and "./install.sh hunk" or "inside tmux")
      assert(#calls == before + 1, "Missing prerequisites must stop before fetching or calling tmux")
    end
    missing_hunk, missing_tmux = false, false
    viewer = "Diffview"
  end)
  test("tmux targeting and launch failures are reported", function()
    viewer = "Hunk"
    vim.env.TMUX, vim.env.TMUX_PANE = "/tmp/test-tmux,123,0", "%1"
    for _, command_name in ipairs({ "display-message", "split-window", "new-window" }) do
      destination = command_name == "new-window" and "New tmux window" or "Right-hand tmux pane"
      tmux_error = { command = command_name, message = "tmux test failure: " .. command_name }
      invoke(review.pr, tmux_error.message)
    end
    tmux_error = nil
    viewer, destination = "Diffview", "Right-hand tmux pane"
  end)
  local path = temp .. "/reviews/github.com/acme/api/pr-42"
  test("worktree and tmux launch open the exact PR revision", function()
    vim.env.TMUX, vim.env.TMUX_PANE = "/tmp/test-tmux,123,0", "%1"
    selection = 2
    local before_prompts, before_choices = #prompts, #choices
    invoke(function()
      review.pr(true)
    end)
    assert(#prompts == before_prompts)
    assert(#choices == before_choices + 1, "Worktree reviews must skip viewer and destination choices")
    selection = "manual"
    worktrees[#worktrees + 1] = { repo = a.repo, path = path }
    assert(git(path, "rev-parse", "HEAD") == a.head)
    assert(git(path, "symbolic-ref", "--short", "HEAD") == "review/pr-42")
    local args = launches[#launches]
    assert(args[4] == "$9:" and args[6] == "api/pr-42" and args[8] == path)
    assert(args[#args]:find(a.base .. ".." .. a.head, 1, true))
    assert(args[#args]:find("--imply-local", 1, true), "PR worktree diff needs real files for LSP navigation")
  end)
  test("matching clean worktree is reused", function()
    invoke(function()
      review.pr(true)
    end)
    assert(git(path, "rev-parse", "HEAD") == a.head)
  end)
  test("removed worktree can be reopened using its retained review branch", function()
    git(a.repo, "worktree", "remove", path)
    git(a.repo, "config", "--unset", "branch.review/pr-42.diffview-pr")
    invoke(function()
      review.pr(true)
    end, "not registered for this PR")
    assert(not vim.uv.fs_stat(path))
    git(a.repo, "config", "branch.review/pr-42.diffview-pr", a.pr.url)
    invoke(function()
      review.pr(true)
    end)
    assert(git(path, "rev-parse", "HEAD") == a.head)
    assert(git(path, "symbolic-ref", "--short", "HEAD") == "review/pr-42")
  end)
  test("blank PR prompt in review branch remembers the GitHub PR", function()
    vim.cmd.cd(path)
    reply = ""
    local before = #calls
    invoke(review.pr)
    local requested
    for index = before + 1, #calls do
      if calls[index].args[1] == "gh" then
        requested = calls[index].args[4]
      end
    end
    assert(requested == a.pr.url)
    assert(opened[#opened][1] == "-C" .. path)
    local before_prompts = #prompts
    before = #calls
    review.branch()
    assert(vim.wait(5000, function()
      return #prompts > before_prompts
    end, 5))
    assert(prompts[#prompts].default == "origin/develop")
    requested = nil
    for index = before + 1, #calls do
      if calls[index].args[1] == "gh" then
        requested = calls[index].args[4]
      end
    end
    assert(requested == a.pr.url)
    vim.cmd.cd(a.repo)
    reply = "42"
  end)
  test("dirty worktree is preserved", function()
    write(path .. "/example.txt", "keep my work")
    invoke(function()
      review.pr(true)
    end, "local changes")
    assert(vim.fn.readfile(path .. "/example.txt")[1] == "keep my work")
    git(path, "restore", "example.txt")
  end)
  test("clean worktree fast-forwards when PR advances", function()
    git(a.seed, "switch", "feature")
    local next_head = commit(a.seed, "example.txt", "PR second commit")
    git(a.seed, "push", a.bare, "HEAD:refs/pull/42/head")
    a.pr.headRefOid = next_head
    invoke(function()
      review.pr(true)
    end)
    assert(git(path, "rev-parse", "HEAD") == next_head)
  end)
  test("PR updates cannot overwrite ignored local files", function()
    local before = git(path, "rev-parse", "HEAD")
    local exclude = git(path, "rev-parse", "--git-path", "info/exclude")
    write(exclude, "local-only.txt")
    write(path .. "/local-only.txt", "keep ignored data")
    a.pr.headRefOid = commit(a.seed, "local-only.txt", "incoming tracked file")
    git(a.seed, "push", a.bare, "HEAD:refs/pull/42/head")
    invoke(function()
      review.pr(true)
    end, "overwritten by merge")
    assert(vim.fn.readfile(path .. "/local-only.txt")[1] == "keep ignored data")
    assert(git(path, "rev-parse", "HEAD") == before)
    vim.fn.delete(path .. "/local-only.txt")
    invoke(function()
      review.pr(true)
    end)
    assert(git(path, "rev-parse", "HEAD") == a.pr.headRefOid)
  end)
  test("local review commits are preserved", function()
    local local_head = commit(path, "local.txt", "keep my commit")
    invoke(function()
      review.pr(true)
    end, "local commits or diverged history")
    assert(git(path, "rev-parse", "HEAD") == local_head)
    git(a.repo, "worktree", "remove", path)
    invoke(function()
      review.pr(true)
    end, "local commits or diverged history")
    assert(not vim.uv.fs_stat(path))
    assert(git(a.repo, "rev-parse", "review/pr-42") == local_head)
  end)
  test("same PR number in another repository has a separate worktree", function()
    vim.cmd.cd(b.repo)
    metadata = b.pr
    local other = temp .. "/reviews/github.com/acme/web/pr-42"
    vim.fn.mkdir(other, "p")
    write(other .. "/keep.txt", "unrelated directory")
    invoke(function()
      review.pr(true)
    end, "already occupied")
    assert(vim.fn.readfile(other .. "/keep.txt")[1] == "unrelated directory")
    vim.fn.delete(other, "rf")
    git(a.repo, "worktree", "add", "--detach", other, a.head)
    invoke(function()
      review.pr(true)
    end, "not this PR's review worktree")
    assert(git(other, "rev-parse", "HEAD") == a.head)
    git(a.repo, "worktree", "remove", other)
    git(b.repo, "worktree", "add", "-b", "unrelated-review", other, b.head)
    invoke(function()
      review.pr(true)
    end, "not this PR's review worktree")
    assert(git(other, "symbolic-ref", "--short", "HEAD") == "unrelated-review")
    git(b.repo, "worktree", "remove", other)
    invoke(function()
      review.pr(true)
    end)
    worktrees[#worktrees + 1] = { repo = b.repo, path = other }
    assert(git(other, "rev-parse", "HEAD") == b.head)
  end)
end, debug.traceback)

-- No real tmux processes are launched by this suite. Remove worktrees before repos.
for _, tree in ipairs(worktrees) do
  if vim.uv.fs_stat(tree.path) then
    git(tree.repo, "worktree", "remove", "--force", tree.path)
  end
end
vim.fn.chdir(config)
vim.fn.delete(temp, "rf")
if not ok then
  error(err)
end
print(string.format("%d Diffview tests passed", passed))
