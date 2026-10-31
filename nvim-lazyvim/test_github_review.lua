-- Offline integration tests with the pinned Diffview plugin and real Git.
-- Run: nvim --headless -u NONE -i NONE -l nvim/test_github_review.lua
local config = vim.fs.dirname(vim.fs.abspath(debug.getinfo(1, "S").source:sub(2)))
local plugin = vim.fn.stdpath("data") .. "/lazy/diffview.nvim"
assert(vim.uv.fs_stat(plugin .. "/lua/diffview/init.lua"), "Install the pinned Diffview plugin first")
vim.opt.rtp:prepend(plugin)
vim.opt.rtp:prepend(config)
vim.o.swapfile, vim.o.hidden = false, true
vim.o.list, vim.o.conceallevel = true, 3
local temp = vim.fn.tempname() .. " github review tests"
vim.fn.mkdir(temp, "p")
temp = assert(vim.uv.fs_realpath(temp))
vim.env.NVIM_LOG_FILE, vim.env.XDG_CACHE_HOME = temp .. "/nvim.log", temp .. "/cache"
vim.env.GIT_CONFIG_GLOBAL, vim.env.GIT_CONFIG_SYSTEM, vim.env.GIT_TERMINAL_PROMPT = "/dev/null", "/dev/null", "0"
local api, system = vim.api, vim.system
local requests, messages, urls, providers = {}, {}, {}, {}
local passed, pending, blob_calls = 0, 0, 0
local blob_requests

local function git(repo, ...)
  local args = vim.list_extend({ "git" }, { ... })
  local result = system(args, { cwd = repo, text = true }):wait()
  assert(result.code == 0, table.concat(args, " ") .. "\n" .. result.stderr)
  return vim.trim(result.stdout)
end
local lock = vim.json.decode(table.concat(vim.fn.readfile(config .. "/lazy-lock.json"), "\n"))
assert(git(plugin, "rev-parse", "HEAD") == lock["diffview.nvim"].commit, "Diffview differs from lazy-lock.json")

local function write(repo, path, lines)
  vim.fn.writefile(lines, repo .. "/" .. path)
end
local function commit(repo, message)
  git(repo, "add", "-A")
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
    message
  )
  return git(repo, "rev-parse", "HEAD")
end
local function fixture(name)
  local repo = temp .. "/" .. name
  git(temp, "init", "-b", "main", repo)
  write(repo, "main.txt", { "alpha", "before", "gamma", "delta" })
  write(repo, "removed.txt", { "removed first", "removed second", "removed third" })
  write(repo, "old.txt", { "rename first", "rename second", "rename third", "rename fourth", "rename fifth" })
  local base = commit(repo, "base")
  git(repo, "switch", "-c", "feature")
  write(repo, "main.txt", { "alpha", "after", "gamma", "delta" })
  git(repo, "mv", "old.txt", "renamed.txt")
  write(repo, "renamed.txt", { "rename first", "rename second", "rename third", "rename fourth", "rename changed" })
  git(repo, "rm", "removed.txt")
  local head = commit(repo, "change")
  git(repo, "switch", "main")
  write(repo, "unrelated.txt", { "base branch advanced" })
  local target = commit(repo, "advance base")
  git(repo, "switch", "feature")
  return {
    repo = repo,
    base = base,
    head = head,
    target = target,
    url = "https://github.com/acme/" .. name .. "/pull/42",
  }
end
local function thread(id, path, side, line, body)
  return {
    id = id,
    kind = "thread",
    url = "https://github.com/acme/repo/pull/42#discussion_r" .. id,
    createdAt = "2026-10-20T10:00:00Z",
    path = path,
    side = side,
    line = line,
    isResolved = false,
    isOutdated = false,
    subjectType = "LINE",
    comments = { { id = "comment-" .. id, author = "alice", createdAt = "2026-10-20T10:00:00Z", body = body } },
  }
end
local literal = "a > b, <> &; &gt; stays literal. café λ 🦊"
local function response(f)
  local items = {
    thread("right", "main.txt", "RIGHT", 2, literal .. "\r\nCRLF and\ttab."),
    thread("left", "main.txt", "LEFT", 2, "Original line comment."),
    thread("range", "main.txt", "RIGHT", 3, "Range comment."),
    thread("rename", "renamed.txt", "RIGHT", 5, "Renamed file comment."),
    thread("oldname", "old.txt", "LEFT", 2, "Original filename comment."),
    thread("delete", "removed.txt", "LEFT", 2, "Deleted file comment."),
    thread("outdated", "main.txt", "RIGHT", 2, "OUTDATED MUST NOT APPEAR"),
    thread("file", "main.txt", "RIGHT", nil, "Whole file comment."),
    { id = "discussion", kind = "discussion", comments = { { author = "bob", body = "GENERAL MUST NOT APPEAR" } } },
    { id = "review", kind = "review", comments = { { author = "carol", body = "SUMMARY MUST NOT APPEAR" } } },
  }
  items[1].isResolved = true
  items[1].comments[2] =
    { id = "reply", author = "bob", createdAt = "2026-10-20T11:00:00Z", body = "Reply also keeps > literal." }
  items[3].startLine, items[3].startSide = 2, "RIGHT"
  items[7].isOutdated, items[8].subjectType = true, "FILE"
  return {
    pr = {
      number = 42,
      title = "pull request",
      url = f.url,
      author = "author",
      state = "OPEN",
      isDraft = false,
      body = "DESCRIPTION MUST NOT APPEAR",
      baseRefName = "main",
      headRefName = "feature",
      baseRefOid = f.target,
      headRefOid = f.head,
    },
    items = items,
    fetchedAt = "2026-10-20T12:30:00Z",
  }
end

vim.notify = function(message)
  messages[#messages + 1] = message
end
vim.ui.open = function(url)
  urls[#urls + 1] = url
  return {
    wait = function()
      return { code = 0 }
    end,
  }
end
-- Headless redraws do not reliably run providers. Retain the public callbacks
-- so draw() can exercise the stale-buffer guard before inspecting real marks.
local set_provider = api.nvim_set_decoration_provider
api.nvim_set_decoration_provider = function(namespace, callbacks)
  providers[namespace] = callbacks
  return set_provider(namespace, callbacks)
end
vim.system = function(args, opts, callback)
  if vim.fs.basename(args[1]) == "python3" and args[2]:match("/github%-review/fetch%.py$") then
    assert(args[2] == config .. "/github-review/fetch.py" and type(callback) == "function")
    local request = { callback = callback }
    requests[#requests + 1] = request
    return {
      kill = function()
        request.killed = true
      end,
      wait = function()
        request.reaped = true
        return { code = 143 }
      end,
    }
  end
  if args[1] == "git" and args[2] == "show" then
    blob_calls = blob_calls + 1
  end
  if blob_requests and args[1] == "git" and args[2] == "show" then
    local request = { callback = callback, result = system(args, opts):wait() }
    blob_requests[#blob_requests + 1] = request
    return {
      kill = function()
        request.killed = true
      end,
      wait = function()
        request.reaped = true
        return { code = 143 }
      end,
    }
  end
  assert(args[1] ~= "gh", "The suite must never contact GitHub")
  if callback then
    pending = pending + 1
    return system(args, opts, function(result)
      callback(result)
      vim.schedule(function()
        pending = pending - 1
      end)
    end)
  end
  return system(args, opts)
end
local function wait_for(predicate, message)
  assert(vim.wait(5000, predicate, 5), message or "Operation timed out")
end
local function settle()
  local elapsed = false
  vim.defer_fn(function()
    elapsed = true
  end, 50)
  wait_for(function()
    return elapsed and pending == 0
  end)
end
local function deliver(request, payload, failure)
  assert(not request.delivered, "Request already answered")
  request.delivered = true
  request.callback({
    code = failure and 1 or 0,
    stdout = failure and "" or vim.json.encode(payload),
    stderr = failure or "",
  })
  settle()
end
local review = require("config.github_review")
local diffview = require("diffview")
diffview.setup({ use_icons = false, hooks = {
  view_closed = function(view)
    review.close(view)
  end,
} })
vim.cmd.runtime("plugin/diffview.lua")

-- Read the actual marks and their window scopes, rather than module state.
local function draw(win)
  local marks, buf = {}, api.nvim_win_get_buf(win)
  for _, callbacks in pairs(providers) do
    if callbacks.on_buf then
      callbacks.on_buf("buf", buf, api.nvim_buf_get_changedtick(buf))
    end
    if callbacks.on_win then
      callbacks.on_win("win", win, buf, 0, api.nvim_buf_line_count(buf))
    end
  end
  for name, namespace in pairs(api.nvim_get_namespaces()) do
    if name:match("^GitHubReview") then
      local stored = api.nvim_buf_get_extmarks(buf, namespace, 0, -1, { details = true })
      local scope = api.nvim__ns_get(namespace).wins
      if #stored > 0 then
        assert(scope and #scope > 0, "Review decorations must have an explicit window scope")
      end
      if scope and vim.tbl_contains(scope, win) then
        for _, mark in ipairs(stored) do
          assert(mark[4].virt_lines, "Review decoration is not inline virtual lines")
          marks[#marks + 1] = { buf = buf, row = mark[2], col = mark[3], opts = mark[4] }
        end
      end
    end
  end
  table.sort(marks, function(a, b)
    return a.row < b.row
  end)
  return marks
end
local function text(marks, separator)
  local rows = {}
  for _, mark in ipairs(marks) do
    for _, chunks in ipairs(mark.opts.virt_lines) do
      local row = {}
      for _, chunk in ipairs(chunks) do
        row[#row + 1] = chunk[1]
      end
      rows[#rows + 1] = table.concat(row)
    end
  end
  return table.concat(rows, separator or "")
end
local function pane(view, side)
  return view.cur_layout[side].id
end
local function contains(view, side, needle)
  return text(draw(pane(view, side))):find(needle, 1, true) ~= nil
end
local function select_file(view, path)
  local opened = false
  view.emitter:on("file_open_post", function(_, entry)
    if entry.path == path then
      opened = true
      return true
    end
  end)
  view:set_file_by_path(path, false, true)
  wait_for(function()
    return opened
  end, "Diffview did not open " .. path)
  settle()
end
local function open(f, revision, local_changes)
  vim.cmd.cd(f.repo)
  revision = revision or (f.base .. ".." .. f.head)
  diffview.open(local_changes and { revision, "--imply-local" } or { revision })
  local view = assert(require("diffview.lib").get_current_view())
  wait_for(function()
    return view.initialized and view.cur_entry and view.cur_entry.opened and view.cur_layout:is_valid()
  end)
  select_file(view, "main.txt")
  local snapshot =
    { wins = api.nvim_tabpage_list_wins(view.tabpage), bufs = api.nvim_list_bufs(), win = api.nvim_get_current_win() }
  local count = #requests
  review.attach(f.repo, f.url, revision)
  wait_for(function()
    return #requests > count
  end, "Attaching did not start the reader")
  return view, requests[#requests], snapshot
end
local function close(view)
  if api.nvim_tabpage_is_valid(view.tabpage) then
    api.nvim_set_current_tabpage(view.tabpage)
    diffview.close()
    settle()
  end
end
local function same_layout(view, snapshot)
  assert(vim.deep_equal(api.nvim_tabpage_list_wins(view.tabpage), snapshot.wins), "Comments opened another window")
  assert(vim.deep_equal(api.nvim_list_bufs(), snapshot.bufs), "Comments created an extra buffer")
  assert(api.nvim_get_current_win() == snapshot.win, "Comments moved focus")
end
local function absent(view)
  assert(#draw(pane(view, "a")) == 0 and #draw(pane(view, "b")) == 0, "Unsafe or hidden comments were drawn")
end
local function test(name, fn)
  fn()
  passed = passed + 1
  print("PASS " .. name)
end

local ok, err = xpcall(function()
  local a, b = fixture("api"), fixture("web")
  test("inline comments preserve source text, sides, ranges, replies and literal prose", function()
    local view, request, snapshot = open(a)
    local original = {}
    for _, side in ipairs({ "a", "b" }) do
      original[side] = api.nvim_buf_get_lines(api.nvim_win_get_buf(pane(view, side)), 0, -1, false)
    end
    deliver(request, response(a))
    same_layout(view, snapshot)
    local left, right = draw(pane(view, "a")), draw(pane(view, "b"))
    assert(text(right):find(literal, 1, true), "Literal >, entities or Unicode were transformed")
    assert(text(right):find("Reply also keeps > literal.", 1, true), "Thread replies are missing")
    assert(
      text(right):find("@bob", 1, true) and text(right):lower():find("resolved", 1, true),
      "Thread author/status missing"
    )
    assert(not text(right):find("[\r\t]"), "CRLF or tabs leaked into virtual lines")
    assert(
      text(left):find("Original line comment.", 1, true) and not text(left):find(literal, 1, true),
      "Comments use the wrong pane"
    )
    assert(not text(right):find("MUST NOT APPEAR", 1, true), "Non-inline or outdated discussion was drawn")
    for _, mark in ipairs(right) do
      local prose = text({ mark })
      if prose:find(literal, 1, true) then
        assert(mark.row == 1 and not mark.opts.virt_lines_above, "Line comment is not below line 2")
      end
      if prose:find("Range comment.", 1, true) then
        assert(mark.row == 2 and not mark.opts.virt_lines_above, "Range is not anchored below its final line")
      end
      if prose:find("Whole file comment.", 1, true) then
        assert(mark.row == 0, "File comment is not at the file top")
      end
    end
    assert(contains(view, "b", "Range comment.") and contains(view, "b", "Whole file comment."))
    for _, side in ipairs({ "a", "b" }) do
      assert(
        vim.deep_equal(original[side], api.nvim_buf_get_lines(api.nvim_win_get_buf(pane(view, side)), 0, -1, false)),
        "Comments changed source text"
      )
    end
    close(view)
  end)
  test("switching files draws rename and deletion comments only in the active panes", function()
    local view, request = open(a)
    deliver(request, response(a))
    select_file(view, "renamed.txt")
    assert(contains(view, "b", "Renamed file comment.") and contains(view, "a", "Original filename comment."))
    assert(not contains(view, "b", literal), "Previous file comments survived a file switch")
    select_file(view, "removed.txt")
    assert(contains(view, "a", "Deleted file comment.") and #draw(pane(view, "b")) == 0)
    select_file(view, "main.txt")
    assert(contains(view, "b", literal), "Returning to a file lost its comments")
    close(view)
  end)
  test("comments wrap to pane width and stay scoped to Diffview windows", function()
    local view, request = open(a)
    local data = response(a)
    data.items[1].comments[1].body = string.rep("long > comment words ", 20)
    deliver(request, data)
    local win = pane(view, "b")
    api.nvim_win_set_width(win, 42)
    api.nvim_exec_autocmds("WinResized", {})
    settle()
    local marks = draw(win)
    local info = vim.fn.getwininfo(win)[1]
    for row in text(marks, "\n"):gmatch("[^\n]+") do
      assert(vim.fn.strdisplaywidth(row) <= info.width - info.textoff, "A virtual line overflows its pane")
    end
    assert(#marks > 0 and #text(marks) > 300, "Wrapping discarded comment content")
    local buf = api.nvim_win_get_buf(win)
    vim.cmd("tabnew")
    local other = api.nvim_get_current_win()
    api.nvim_win_set_buf(other, buf)
    assert(#draw(other) == 0, "Comments leaked into another tab sharing the source buffer")
    vim.cmd("tabclose")
    api.nvim_set_current_win(win)
    vim.cmd("vsplit")
    local split = api.nvim_get_current_win()
    assert(#draw(split) == 0, "Comments leaked into another split sharing the source buffer")
    api.nvim_win_close(split, true)
    close(view)
  end)
  test("toggle and refresh reuse inline state without changing the layout", function()
    local view, request, snapshot = open(a)
    deliver(request, response(a))
    local count = #requests
    review.toggle()
    absent(view)
    same_layout(view, snapshot)
    review.toggle()
    settle()
    assert(contains(view, "b", literal) and #requests == count, "Showing comments refetched or lost them")
    review.refresh()
    deliver(requests[#requests], nil, "GitHub is unavailable")
    assert(contains(view, "b", literal), "Refresh error discarded valid comments")
    assert(table.concat(messages, "\n"):find("GitHub is unavailable", 1, true), "Refresh error was hidden")
    review.refresh()
    local updated = response(a)
    updated.items[1].comments[1].body = "Updated comment."
    deliver(requests[#requests], updated)
    assert(contains(view, "b", "Updated comment.") and not contains(view, "b", literal))
    review.open_pr()
    assert(urls[#urls] == a.url)
    same_layout(view, snapshot)
    close(view)
  end)
  test("responses remain in their own views and superseded requests cannot overwrite newer comments", function()
    local first, old = open(a)
    review.refresh()
    local fresh = requests[#requests]
    assert(old.killed, "Refresh did not cancel the previous request")
    local second, second_request, snapshot = open(b)
    local updated = response(a)
    updated.items[1].comments[1].body = "Newest first-view comment."
    deliver(fresh, updated)
    deliver(old, response(a))
    deliver(second_request, response(b))
    same_layout(second, snapshot)
    assert(api.nvim_get_current_tabpage() == second.tabpage, "Inactive response changed tabs")
    assert(contains(first, "b", "Newest first-view comment.") and not contains(first, "b", literal))
    assert(contains(second, "b", literal) and not contains(second, "b", "Newest first-view comment."))
    close(second)
    close(first)
  end)
  test("file switches and closing cancel stale Git blob checks", function()
    local view, request = open(a)
    blob_requests = {}
    deliver(request, response(a))
    assert(#blob_requests == 2, "Both source panes must be checked before drawing comments")
    absent(view)
    select_file(view, "renamed.txt")
    assert(blob_requests[1].killed and blob_requests[2].killed, "File switch left old blob checks running")
    assert(#blob_requests == 4)
    for index = 3, 4 do
      blob_requests[index].callback(blob_requests[index].result)
    end
    settle()
    assert(contains(view, "b", "Renamed file comment."))
    for index = 1, 2 do
      blob_requests[index].callback(blob_requests[index].result)
    end
    settle()
    assert(
      contains(view, "b", "Renamed file comment.") and not contains(view, "b", literal),
      "Stale blob checks decorated another file"
    )
    select_file(view, "main.txt")
    local pending_checks = { blob_requests[5], blob_requests[6] }
    close(view)
    for _, check in ipairs(pending_checks) do
      assert(check.killed, "Closing left a blob check running")
      check.callback(check.result)
    end
    settle()
    blob_requests = nil
    for _, win in ipairs(api.nvim_list_wins()) do
      assert(#draw(win) == 0, "Late blob check left orphaned comments")
    end
  end)
  test("closing removes decorations and ignores a late reader response", function()
    local view, request = open(a)
    deliver(request, response(a))
    local buf = api.nvim_win_get_buf(pane(view, "b"))
    vim.cmd("tabnew")
    local shared = api.nvim_get_current_win()
    api.nvim_win_set_buf(shared, buf)
    api.nvim_set_current_tabpage(view.tabpage)
    review.refresh()
    local late = requests[#requests]
    close(view)
    assert(late.killed, "Closing did not cancel the pending reader")
    deliver(late, response(a))
    assert(not api.nvim_tabpage_is_valid(view.tabpage), "Late response recreated the review")
    for name, namespace in pairs(api.nvim_get_namespaces()) do
      if name:match("^GitHubReview") then
        for _, buffer in ipairs(api.nvim_list_bufs()) do
          assert(#api.nvim_buf_get_extmarks(buffer, namespace, 0, -1, {}) == 0, "Closing left stored review marks")
        end
      end
    end
    for _, win in ipairs(api.nvim_list_wins()) do
      assert(#draw(win) == 0, "Closing left orphaned annotations")
    end
    if api.nvim_win_is_valid(shared) then
      api.nvim_set_current_win(shared)
      vim.cmd("tabclose")
    end
  end)
  test("empty or stale PR data never projects published coordinates onto the wrong comparison", function()
    for _, variant in ipairs({ "empty", "outdated", "base", "head", "pr" }) do
      local revision = variant == "base" and (a.target .. ".." .. a.head) or nil
      local view, request = open(a, revision)
      local data = response(a)
      if variant == "empty" then
        data.items = {}
      end
      if variant == "outdated" then
        for _, item in ipairs(data.items) do
          item.isOutdated = true
        end
      end
      if variant == "head" then
        data.pr.headRefOid = a.base
      end
      if variant == "pr" then
        data.pr.url = b.url
      end
      deliver(request, data)
      absent(view)
      close(view)
    end
  end)
  test("unsaved and working-tree edits hide published comments", function()
    local view, request = open(a)
    deliver(request, response(a))
    local buf = api.nvim_win_get_buf(pane(view, "b"))
    local original = api.nvim_buf_get_lines(buf, 0, -1, false)
    local calls = blob_calls
    vim.bo[buf].modifiable = true
    api.nvim_buf_set_lines(buf, 0, 0, false, { "unsaved insertion" })
    assert(#draw(pane(view, "b")) == 0, "An edited buffer retained stale coordinates before TextChanged")
    for _, event in ipairs({ "TextChanged", "TextChangedI", "BufWritePost" }) do
      api.nvim_exec_autocmds(event, { buffer = buf })
      settle()
      assert(#draw(pane(view, "b")) == 0, event .. " restored invalid coordinates")
    end
    assert(blob_calls == calls, "Text changes reread immutable Git blobs")
    api.nvim_buf_set_lines(buf, 0, -1, false, original)
    api.nvim_exec_autocmds("TextChanged", { buffer = buf })
    settle()
    assert(contains(view, "b", literal), "Restoring the published content did not restore comments")
    assert(blob_calls == calls, "Restoring published content reread immutable Git blobs")
    vim.bo[buf].modified = false
    close(view)
    write(a.repo, "main.txt", { "local insertion", "alpha", "after", "gamma", "delta" })
    view, request = open(a, nil, true)
    deliver(request, response(a))
    assert(#draw(pane(view, "b")) == 0, "Working-tree changes retained stale coordinates")
    close(view)
    git(a.repo, "restore", "--", "main.txt")
  end)
end, debug.traceback)

for _, view in ipairs(vim.list_extend({}, require("diffview.lib").views)) do
  pcall(close, view)
end
vim.fn.chdir(config)
vim.api.nvim_create_autocmd("VimLeave", {
  once = true,
  callback = function()
    vim.fn.delete(temp, "rf")
  end,
})
if not ok then
  error(err)
end
print(string.format("%d GitHub inline review integration tests passed", passed))
