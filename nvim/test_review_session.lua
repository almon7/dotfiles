-- Offline review lifecycle tests: real Git/session records, fake editor and tmux transitions.
local config = vim.fs.dirname(vim.fs.abspath(debug.getinfo(1, "S").source:sub(2)))
vim.opt.rtp:prepend(config)
local temp = vim.fn.tempname() .. " review sessions"
vim.fn.mkdir(temp, "p")
temp = assert(vim.uv.fs_realpath(temp))
local system, expand, command = vim.system, vim.fn.expand, vim.cmd
local view, token, helper_error, quit_error, process_table
local calls, notices, diffs = {}, {}, {}
local quits, closes, probes, cleanups, passed = 0, 0, 0, 0, 0
local pending
local before_ref_update
local function run(args, cwd, input)
  local value = system(args, {
    cwd = cwd or temp,
    stdin = input,
    text = true,
    env = { GIT_CONFIG_GLOBAL = "/dev/null", GIT_CONFIG_SYSTEM = "/dev/null" },
  }):wait()
  assert(value.code == 0, value.stderr)
  return vim.trim(value.stdout)
end
local function write(path, value)
  vim.fn.writefile({ value }, path)
end
local function read(path)
  return vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
end
local function test(name, fn)
  fn()
  passed = passed + 1
  print("PASS " .. name)
end
vim.fn.expand = function(value, ...)
  return value == "~/reviews" and temp .. "/reviews" or expand(value, ...)
end
vim.notify = function(message)
  notices[#notices + 1] = message
end
vim.env.TMUX, vim.env.TMUX_PANE = "/tmp/review-test,123,0", "%7"
package.loaded.diffview = {
  open = function(args)
    diffs[#diffs + 1] = args
  end,
  close = function()
    closes = closes + 1
  end,
}
package.loaded["diffview.lib"] = {
  get_current_view = function()
    return view
  end,
}
package.loaded["config.review_cleanup"] = {
  preflight = function()
    probes = probes + 1
  end,
  cleanup = function()
    cleanups = cleanups + 1
  end,
}
vim.cmd = setmetatable({ cd = command.cd }, {
  __call = function(_, text)
    assert(text == "qall", text)
    quits = quits + 1
    if quit_error then
      error(quit_error)
    end
  end,
})
vim.system = function(args, opts, callback)
  calls[#calls + 1] = args
  if args[1] == "git" and args[3] == "update-ref" and before_ref_update then
    local hook = before_ref_update
    before_ref_update = nil
    hook()
  end
  local value
  if args[1] == "ps" then
    value = {
      code = 0,
      stdout = args[2] == "-A" and (process_table or (vim.uv.os_getpid() .. " 1\n")) or "process-start",
      stderr = "",
    }
  elseif args[1] == "tmux" then
    if args[4] == "set-option" then
      token = args[#args]
    end
    value = { code = 0, stdout = args[4] == "show-options" and token or "", stderr = "" }
  elseif args[1] == vim.v.progpath and args[2] == "-l" then
    pending = function()
      callback({ code = helper_error and 1 or 0, stderr = helper_error or "", stdout = "" })
    end
    return {}
  else
    return system(args, opts, callback)
  end
  if callback then
    callback(value)
  end
  return {
    wait = function()
      return value
    end,
  }
end
local session = require("config.review_session")
local repo = temp .. "/repo"
run({ "git", "init", "-b", "main", repo })
write(repo .. "/file", "original")
run({ "git", "add", "file" }, repo)
run({
  "git",
  "-c",
  "user.name=Test",
  "-c",
  "user.email=test@example.com",
  "-c",
  "commit.gpgsign=false",
  "commit",
  "-m",
  "base",
}, repo)
local head = run({ "git", "rev-parse", "HEAD" }, repo)
local pr =
  { identity = "github.com/acme/repo", url = "https://github.com/acme/repo/pull/42", number = 42, headRefOid = head }
local ctx
local function make_stale(value)
  local saved = read(value.record)
  saved.owner_start = "old process"
  local oid = run({ "git", "hash-object", "-w", "--stdin" }, repo, vim.json.encode(saved))
  run({ "git", "update-ref", saved.registry, oid }, repo)
end
local function finish_probe()
  assert(pending, "No preflight was started")
  local fn = pending
  pending = nil
  fn()
  vim.wait(100, function()
    return pending == nil
  end)
  vim.wait(10)
end
local ok, err = xpcall(function()
  test("ordinary diffs close without a managed session", function()
    view = { adapter = { ctx = { toplevel = repo } } }
    session.close()
    assert(closes == 1 and quits == 0)
    view = nil
    session.close()
    assert(notices[#notices] == "No review to close")
  end)
  test("reserve records explicit identity and serialises pending opens", function()
    ctx = session.reserve(repo, pr)
    assert(ctx.head == head and ctx.pr_url == pr.url and ctx.common_dir == repo .. "/.git")
    local again, reason = pcall(session.reserve, repo, pr)
    assert(not again and reason:find("starting", 1, true))
  end)
  test("managed start opens real files and registers the owning pane", function()
    vim.fn.mkdir(vim.fs.dirname(ctx.path), "p")
    run({ "git", "worktree", "add", "-b", ctx.branch, ctx.path, head }, repo)
    session.prepare(ctx, head .. "^.." .. head)
    session.start(ctx.record, vim.uv.os_getpid())
    assert(token == ctx.token and read(ctx.record).pane == "%7")
    assert(diffs[#diffs][3] == "--imply-local" and vim.fn.getcwd() == ctx.path)
  end)
  test("opening an active review focuses its pane without a second launch", function()
    local before = #diffs
    assert(session.reserve(repo, pr) == nil)
    assert(#diffs == before and calls[#calls][4] == "select-pane")
  end)
  test("a foreign diff closes only that view inside a managed editor", function()
    view = { adapter = { ctx = { toplevel = repo } } }
    session.close()
    assert(closes == 2 and quits == 0)
    view = nil
  end)
  test("unnamed modified buffers block cleanup before probes", function()
    local buffer = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { "keep this" })
    session.close()
    assert(not pending and notices[#notices]:find("[No Name]", 1, true))
    vim.api.nvim_buf_delete(buffer, { force = true })
  end)
  test("preflight failures leave the editor and request untouched", function()
    helper_error = "Unlisted extra file remains: .env"
    session.close()
    finish_probe()
    assert(quits == 0 and not vim.uv.fs_stat(ctx.state_dir .. "/request.json"))
    assert(notices[#notices]:find(".env", 1, true))
    helper_error = nil
  end)
  test("embedded editor includes its TUI ancestor but not launcher siblings", function()
    process_table = vim.uv.os_getpid() .. " 500\n500 400\n400 1\n501 400\n"
    session.start(ctx.record, 400)
    helper_error = "stop after checking ownership"
    session.close()
    local owned = read(ctx.record).owned_pids
    assert(vim.tbl_contains(owned, 500) and vim.tbl_contains(owned, 400))
    assert(not vim.tbl_contains(owned, 501))
    finish_probe()
    session.start(ctx.record, vim.uv.os_getpid())
    process_table, helper_error = nil, nil
  end)
  test("edits made during asynchronous preflight prevent quitting", function()
    session.close()
    local buffer = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { "new work" })
    finish_probe()
    assert(quits == 0)
    vim.api.nvim_buf_delete(buffer, { force = true })
  end)
  test("cancelled quit clears cleanup authorisation", function()
    quit_error = "quit cancelled"
    session.close()
    finish_probe()
    assert(quits == 1 and not vim.uv.fs_stat(ctx.state_dir .. "/request.json"))
    quit_error = nil
  end)
  test("ordinary exits have no cleanup request", function()
    session.run("cleanup", ctx.record)
    assert(cleanups == 0)
  end)
  test("cleanup consumes only the matching one-use request", function()
    write(ctx.state_dir .. "/request.json", vim.json.encode({ token = "other" }))
    assert(not pcall(session.run, "cleanup", ctx.record))
    write(ctx.state_dir .. "/request.json", vim.json.encode({ token = ctx.token }))
    session.run("cleanup", ctx.record)
    session.run("cleanup", ctx.record)
    assert(cleanups == 1)
  end)
  test("headless preflight uses the shared cleanup implementation", function()
    session.run("preflight", ctx.record)
    assert(probes == 1)
  end)
  test("stale records with reused PIDs are replaced", function()
    make_stale(ctx)
    local replacement = session.reserve(repo, pr)
    assert(replacement.token ~= ctx.token)
    assert(not pcall(session.release, ctx))
    ctx = replacement
    session.release(ctx)
    assert(not vim.uv.fs_stat(ctx.state_dir))
  end)
  test("competing stale reservations cannot replace the winner", function()
    ctx = session.reserve(repo, pr)
    make_stale(ctx)
    local winner
    before_ref_update = function()
      winner = session.reserve(repo, pr)
    end
    local acquired = pcall(session.reserve, repo, pr)
    assert(not acquired and winner and vim.uv.fs_stat(winner.record))
    assert(run({ "git", "rev-parse", winner.registry }, repo) == winner.revision_id)
    ctx = winner
  end)
  test("a stale release cannot remove a newer reservation", function()
    make_stale(ctx)
    local winner
    before_ref_update = function()
      winner = session.reserve(repo, pr)
    end
    assert(not pcall(session.release, ctx))
    assert(winner and vim.uv.fs_stat(winner.record))
    assert(run({ "git", "rev-parse", winner.registry }, repo) == winner.revision_id)
    session.release(winner)
  end)
  test("missing stale metadata does not strand a successful reservation", function()
    ctx = session.reserve(repo, pr)
    make_stale(ctx)
    vim.fn.delete(ctx.state_dir, "rf")
    local replacement = session.reserve(repo, pr)
    assert(replacement and vim.uv.fs_stat(replacement.record))
    session.release(replacement)
  end)
  test("shell wrapper releases sessions and preserves failure output", function()
    local fake = temp .. "/fake-nvim"
    vim.fn.writefile({
      "#!/usr/bin/env bash",
      'printf \'%s\\n\' "$*" >> "$REVIEW_TEST_LOG"',
      'if [[ $1 == -c ]]; then exit "${REVIEW_EDITOR_STATUS:-0}"; fi',
      'if [[ ${3:-} == cleanup ]]; then exit "${REVIEW_CLEANUP_STATUS:-0}"; fi',
      "exit 0",
    }, fake)
    vim.fn.setfperm(fake, "rwx------")
    for _, case in ipairs({ { 0, 0 }, { 1, 0 }, { 0, 1 } }) do
      local log = temp .. "/wrapper.log"
      write(log, "")
      local value = system({ "bash", config .. "/review-session.sh", fake, "/unused/context.json" }, {
        cwd = temp,
        text = true,
        stdin = "",
        env = {
          REVIEW_TEST_LOG = log,
          REVIEW_EDITOR_STATUS = tostring(case[1]),
          REVIEW_CLEANUP_STATUS = tostring(case[2]),
        },
      }):wait()
      local output = table.concat(vim.fn.readfile(log), "\n")
      assert(output:find("release", 1, true))
      assert((output:find("cleanup", 1, true) ~= nil) == (case[1] == 0))
      assert((value.code ~= 0) == (case[1] ~= 0 or case[2] ~= 0))
      if value.code ~= 0 then
        assert(value.stdout:find("Cleanup stopped", 1, true))
      end
    end
  end)
end, debug.traceback)
vim.cmd, vim.system, vim.fn.expand = command, system, expand
vim.cmd.cd(config)
vim.fn.delete(temp, "rf")
if not ok then
  error(err)
end
print(string.format("%d review session tests passed", passed))
