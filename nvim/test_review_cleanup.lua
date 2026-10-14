-- Offline cleanup integration tests: real Git worktrees and fake resource probes.
-- Run: nvim --headless -u NONE -i NONE -l nvim/test_review_cleanup.lua
local config = vim.fs.dirname(vim.fs.abspath(debug.getinfo(1, "S").source:sub(2)))
vim.opt.rtp:prepend(config)
local temp = vim.fn.tempname() .. " review cleanup tests"
vim.fn.mkdir(temp, "p")
temp = assert(vim.uv.fs_realpath(temp))
vim.env.NVIM_LOG_FILE = temp .. "/nvim.log"
local system, executable = vim.system, vim.fn.executable
local env = { GIT_CONFIG_GLOBAL = "/dev/null", GIT_CONFIG_SYSTEM = "/dev/null", GIT_TERMINAL_PROMPT = "0" }
local passed, sequence = 0, 0
local failures = {}
local calls, results, before_command, on_script, docker_available, lsof_available
local fixtures = {}

local function command(cwd, args)
  local result = system(args, { cwd = cwd, text = true, env = env }):wait()
  assert(result.code == 0, table.concat(args, " ") .. "\n" .. result.stderr)
  return vim.trim(result.stdout)
end

local function git(cwd, ...)
  return command(cwd, vim.list_extend({ "git" }, { ... }))
end

local function write(path, contents)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  vim.fn.writefile(vim.split(contents, "\n", { plain = true }), path)
end

local function commit(repo, message)
  git(repo, "add", "--all")
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

local function exists(path)
  return vim.uv.fs_lstat(path) ~= nil
end

local function result(code, stdout, stderr)
  return { code = code or 0, signal = 0, stdout = stdout or "", stderr = stderr or "" }
end

vim.fn.executable = function(name)
  if name == "docker" then
    return docker_available and 1 or 0
  elseif name == "lsof" then
    return lsof_available and 1 or 0
  elseif name == "fake-teardown" or name == "fake-verify" then
    return 1
  end
  return executable(name)
end

vim.system = function(args, opts, callback)
  opts = opts or {}
  local call = { args = vim.deepcopy(args), opts = vim.deepcopy(opts) }
  calls[#calls + 1] = call
  if before_command then
    before_command(args, opts)
  end
  local name, answer = vim.fs.basename(args[1])
  if name == "lsof" then
    answer = results.lsof or result(1)
  elseif name == "docker" then
    answer = args[2] == "inspect" and (results.inspect or result(0, "[]")) or (results.docker or result())
  elseif
    name == "git"
    and vim.tbl_contains(args, "worktree")
    and vim.tbl_contains(args, "remove")
    and results.git_remove
  then
    answer = results.git_remove
  elseif name == "git" and vim.tbl_contains(args, "--unset-all") and results.git_metadata then
    answer = results.git_metadata
  elseif name == "fake-teardown" or name == "fake-verify" then
    if on_script then
      on_script(name, opts)
    end
    answer = results[name] or result()
  end
  if answer then
    if callback then
      vim.schedule(function()
        callback(vim.deepcopy(answer))
      end)
    end
    return {
      wait = function(_, timeout)
        call.wait_timeout = timeout
        return vim.deepcopy(answer)
      end,
    }
  end
  opts.env = vim.tbl_extend("force", opts.env or {}, env)
  return system(args, opts, callback)
end

local cleanup = require("config.review_cleanup")

local function project(ctx, entry)
  write(ctx.config_dir .. "/lua/config/review_projects.lua", "return " .. vim.inspect({ [ctx.identity] = entry }))
end

local function fixture()
  sequence = sequence + 1
  local repo = temp .. "/repo " .. sequence
  local path = temp .. "/review " .. sequence
  calls, results, before_command, on_script = {}, {}, nil, nil
  docker_available, lsof_available = false, true
  git(temp, "init", "-b", "main", repo)
  write(repo .. "/example.txt", "base")
  write(repo .. "/.gitignore", "ignored/\nsecret.env")
  local base = commit(repo, "base")
  git(repo, "remote", "add", "origin", "https://github.com/acme/reviews.git")
  git(repo, "worktree", "add", "-b", "review/pr-42", path)
  write(path .. "/example.txt", "review change")
  local head = commit(path, "review")
  local ctx = {
    path = assert(vim.uv.fs_realpath(path)),
    common_dir = assert(vim.uv.fs_realpath(repo .. "/.git")),
    branch = "review/pr-42",
    head = head,
    identity = "github.com/acme/reviews",
    pr_url = "https://github.com/acme/reviews/pull/42",
    config_dir = temp .. "/config " .. sequence,
    owned_pids = { vim.fn.getpid() },
  }
  git(repo, "config", "branch." .. ctx.branch .. ".diffview-pr", ctx.pr_url)
  git(repo, "update-ref", "refs/diffview/github.com/acme/reviews/pr-42/base", base)
  git(repo, "update-ref", "refs/diffview/github.com/acme/reviews/pr-42/head", head)
  write(ctx.config_dir .. "/lua/config/review_projects.lua", "return {}")
  fixtures[#fixtures + 1] = { repo = repo, path = path }
  return ctx, repo, base
end

local function rejected(ctx, fn, pattern)
  local ok, err = pcall(fn or cleanup.preflight, ctx)
  assert(not ok, "Unsafe cleanup was accepted")
  if pattern then
    assert(tostring(err):lower():find(pattern:lower(), 1, true), "Expected " .. pattern .. ", got " .. tostring(err))
  end
  assert(exists(ctx.path), "Rejected cleanup removed the worktree")
  return tostring(err)
end

local function call_index(name, subcommand)
  for index, call in ipairs(calls) do
    if call.args[1] == name and (not subcommand or call.args[2] == subcommand) then
      return index, call
    end
  end
end

local function test(name, fn)
  local success, failure = xpcall(fn, debug.traceback)
  if success then
    passed = passed + 1
    print("PASS " .. name)
  else
    failures[#failures + 1] = name .. "\n" .. failure
    print("FAIL " .. name .. ": " .. failure)
  end
end

local ok, err = xpcall(function()
  test("clean unconfigured review removes only its worktree, branch and own metadata", function()
    local ctx, repo, base = fixture()
    git(repo, "config", "branch." .. ctx.branch .. ".description", "keep user metadata")
    cleanup.preflight(ctx)
    assert(exists(ctx.path), "Preflight mutated the worktree")
    cleanup.cleanup(ctx)
    assert(not exists(ctx.path))
    assert(not git(repo, "for-each-ref", "--format=%(refname)", "refs/heads"):find(ctx.branch, 1, true))
    assert(git(repo, "rev-parse", "HEAD") == base)
    assert(git(repo, "config", "--get", "branch." .. ctx.branch .. ".description") == "keep user metadata")
    assert(git(repo, "rev-parse", "refs/diffview/github.com/acme/reviews/pr-42/head") == ctx.head)
    assert(not git(repo, "worktree", "list", "--porcelain"):find(ctx.path, 1, true))
    local metadata = system(
      { "git", "config", "--get", "branch." .. ctx.branch .. ".diffview-pr" },
      { cwd = repo, env = env }
    ):wait()
    assert(metadata.code == 1, "Owned PR metadata was retained")
    local _, process_call = call_index("lsof")
    assert(process_call.opts.timeout == 10000 or process_call.wait_timeout == 10000)
  end)

  for _, kind in ipairs({ "unstaged", "staged", "untracked", "ignored" }) do
    test(kind .. " changes prevent all cleanup", function()
      local ctx = fixture()
      local path = ctx.path
        .. (kind == "ignored" and "/secret.env" or kind == "untracked" and "/notes.txt" or "/example.txt")
      write(path, "must keep")
      if kind == "staged" then
        git(ctx.path, "add", "example.txt")
      end
      rejected(ctx)
      rejected(ctx, cleanup.cleanup)
      assert(vim.fn.readfile(path)[1] == "must keep")
      assert(not call_index("fake-teardown"))
    end)
  end

  for _, flag in ipairs({ "--assume-unchanged", "--skip-worktree" }) do
    test(flag .. " cannot hide local edits from cleanup", function()
      local ctx = fixture()
      git(ctx.path, "update-index", flag, "example.txt")
      write(ctx.path .. "/example.txt", "hidden local work")
      assert(git(ctx.path, "status", "--porcelain") == "", "Fixture must hide the edit from ordinary status")
      rejected(ctx)
      rejected(ctx, cleanup.cleanup)
      assert(vim.fn.readfile(ctx.path .. "/example.txt")[1] == "hidden local work")
    end)
  end

  test("local commits and a replaced branch prevent cleanup", function()
    local ctx = fixture()
    write(ctx.path .. "/example.txt", "local commit")
    commit(ctx.path, "local work")
    rejected(ctx)
    local other = fixture()
    git(other.path, "switch", "-c", "personal-branch")
    rejected(other)
  end)

  test("wrong repository, PR identity and branch mapping prevent cleanup", function()
    for _, change in ipairs({ "common", "identity", "mapping", "remote" }) do
      local ctx, repo = fixture()
      if change == "common" then
        ctx.common_dir = temp
      elseif change == "identity" then
        ctx.identity = "github.com/somebody/else"
      elseif change == "mapping" then
        git(repo, "config", "branch." .. ctx.branch .. ".diffview-pr", "https://github.com/acme/reviews/pull/99")
      else
        git(repo, "remote", "set-url", "origin", "https://github.com/somebody/else.git")
      end
      rejected(ctx)
    end
  end)

  test("locked worktrees and in-progress Git operations prevent cleanup", function()
    local ctx, repo = fixture()
    git(repo, "worktree", "lock", ctx.path)
    rejected(ctx)
    git(repo, "worktree", "unlock", ctx.path)
    for _, marker in ipairs({
      "MERGE_HEAD",
      "CHERRY_PICK_HEAD",
      "REVERT_HEAD",
      "BISECT_LOG",
      "rebase-merge",
      "rebase-apply",
      "sequencer",
      "index.lock",
    }) do
      local git_dir = git(ctx.path, "rev-parse", "--absolute-git-dir")
      if marker == "rebase-merge" or marker == "rebase-apply" or marker == "sequencer" then
        vim.fn.mkdir(git_dir .. "/" .. marker)
      else
        write(git_dir .. "/" .. marker, ctx.head)
      end
      rejected(ctx)
      vim.fn.delete(git_dir .. "/" .. marker, "rf")
    end
  end)

  test("configured commands run in order with bounded timeouts outside deletion", function()
    local ctx = fixture()
    project(ctx, { teardown = { "fake-teardown", "argument with spaces" }, verify = { "fake-verify" } })
    on_script = function(_, opts)
      assert(opts.cwd == ctx.path)
      assert(exists(ctx.path .. "/.git"), "Script ran after worktree removal")
    end
    cleanup.preflight(ctx)
    assert(not call_index("fake-teardown"), "Preflight ran teardown")
    cleanup.cleanup(ctx)
    local teardown_index, teardown_call = call_index("fake-teardown")
    local verify_index, verify_call = call_index("fake-verify")
    assert(teardown_index and verify_index and teardown_index < verify_index)
    assert(teardown_call.args[2] == "argument with spaces")
    assert(teardown_call.opts.timeout == 60000 or teardown_call.wait_timeout == 60000)
    assert(verify_call.opts.timeout == 60000 or verify_call.wait_timeout == 60000)
    assert(not exists(ctx.path))
  end)

  for _, failing in ipairs({ "fake-teardown", "fake-verify" }) do
    for _, failure in ipairs({ result(1, "", "script failed"), result(124, "", "command timed out") }) do
      test(failing .. " failure or timeout preserves worktree and disposable files", function()
        local ctx = fixture()
        project(ctx, { teardown = { "fake-teardown" }, verify = { "fake-verify" }, disposable_paths = { "ignored" } })
        write(ctx.path .. "/ignored/cache", "keep until verification passes")
        results[failing] = failure
        rejected(ctx, cleanup.cleanup)
        assert(exists(ctx.path .. "/ignored/cache"))
        if failing == "fake-teardown" then
          assert(not call_index("fake-verify"))
        end
      end)
    end
  end

  test("teardown requires verification and commands must be argument lists", function()
    for _, entry in ipairs({
      { teardown = { "fake-teardown" } },
      { teardown = "fake-teardown", verify = { "fake-verify" } },
    }) do
      local ctx = fixture()
      project(ctx, entry)
      rejected(ctx)
    end
  end)

  test("allowlisted ignored and untracked files are removed after verification", function()
    local ctx = fixture()
    project(ctx, { disposable_paths = { "ignored", "generated.txt" } })
    write(ctx.path .. "/ignored/nested/cache", "cache")
    write(ctx.path .. "/generated.txt", "generated")
    cleanup.preflight(ctx)
    assert(exists(ctx.path .. "/ignored/nested/cache"))
    cleanup.cleanup(ctx)
    assert(not exists(ctx.path))
  end)

  test("an unexpected file prevents deletion of every allowlisted file", function()
    local ctx = fixture()
    project(ctx, { disposable_paths = { "ignored" } })
    write(ctx.path .. "/ignored/cache", "cache")
    write(ctx.path .. "/notes.txt", "keep")
    rejected(ctx, cleanup.cleanup)
    assert(exists(ctx.path .. "/ignored/cache") and exists(ctx.path .. "/notes.txt"))
  end)

  test("all disposable paths are validated before any file is deleted", function()
    for _, unsafe in ipairs({ "../outside", ".", ".git", ".GIT", ".git/config", "example.txt", "/tmp/outside" }) do
      local ctx = fixture()
      project(ctx, { disposable_paths = { "ignored", unsafe } })
      write(ctx.path .. "/ignored/cache", "must survive")
      rejected(ctx, cleanup.cleanup)
      assert(exists(ctx.path .. "/ignored/cache"))
    end
  end)

  test("allowlisting a directory containing a tracked file is rejected", function()
    local ctx, repo = fixture()
    write(ctx.path .. "/tracked/file", "tracked")
    ctx.head = commit(ctx.path, "add nested file")
    project(ctx, { disposable_paths = { "tracked" } })
    rejected(ctx, cleanup.cleanup)
    assert(exists(ctx.path .. "/tracked/file"))
    assert(git(repo, "rev-parse", ctx.branch) == ctx.head)
  end)

  test("filesystem aliases cannot bypass tracked-file protection", function()
    local ctx = fixture()
    assert(vim.uv.fs_link(ctx.path .. "/example.txt", ctx.path .. "/alias"))
    project(ctx, { disposable_paths = { "alias" } })
    rejected(ctx, cleanup.cleanup)
    assert(exists(ctx.path .. "/example.txt"))
    if exists(ctx.path .. "/EXAMPLE.TXT") then
      vim.uv.fs_unlink(ctx.path .. "/alias")
      project(ctx, { disposable_paths = { "EXAMPLE.TXT" } })
      rejected(ctx, cleanup.cleanup)
      assert(exists(ctx.path .. "/example.txt"))
      write(ctx.path .. "/tracked/file", "tracked")
      ctx.head = commit(ctx.path, "nested tracked file")
      project(ctx, { disposable_paths = { "TRACKED" } })
      rejected(ctx, cleanup.cleanup)
      assert(exists(ctx.path .. "/tracked/file"))
    end
  end)

  test("symlink ancestors are rejected and final symlinks never follow targets", function()
    local ctx = fixture()
    local outside = temp .. "/outside " .. sequence
    write(outside .. "/precious", "must survive")
    assert(vim.uv.fs_symlink(outside, ctx.path .. "/linked"))
    project(ctx, { disposable_paths = { "linked/precious" } })
    rejected(ctx, cleanup.cleanup)
    assert(exists(outside .. "/precious"))
    project(ctx, { disposable_paths = { "linked" } })
    cleanup.cleanup(ctx)
    assert(not exists(ctx.path))
    assert(vim.fn.readfile(outside .. "/precious")[1] == "must survive")
  end)

  test("nested repositories under disposable directories are preserved", function()
    for _, git_marker in ipairs({ "directory", "file" }) do
      local ctx = fixture()
      project(ctx, { disposable_paths = { "ignored" } })
      write(ctx.path .. "/ignored/cache", "cache")
      local nested = ctx.path .. "/ignored/nested"
      if git_marker == "directory" then
        git(ctx.path, "init", nested)
      else
        write(nested .. "/.git", "gitdir: /somewhere/else")
      end
      rejected(ctx, cleanup.cleanup)
      assert(exists(nested .. "/.git"))
      assert(exists(ctx.path .. "/ignored/cache"))
    end
  end)

  test("files created by teardown are revalidated before disposable deletion", function()
    local ctx = fixture()
    project(ctx, { teardown = { "fake-teardown" }, verify = { "fake-verify" }, disposable_paths = { "ignored" } })
    write(ctx.path .. "/ignored/cache", "must survive")
    on_script = function(name)
      if name == "fake-teardown" then
        write(ctx.path .. "/unexpected-after-teardown", "must survive")
      end
    end
    rejected(ctx, cleanup.cleanup)
    assert(exists(ctx.path .. "/ignored/cache"))
    assert(exists(ctx.path .. "/unexpected-after-teardown"))
  end)

  test("missing lsof, probe errors, malformed output and timeout stop cleanup", function()
    local ctx = fixture()
    lsof_available = false
    rejected(ctx)
    lsof_available = true
    for _, failure in ipairs({
      result(2, "", "permission denied"),
      result(0, "not lsof fields"),
      result(0, "p987654\0"),
      result(0, "cnode\0"),
      result(0, "p987654\0cnode\0xunknown\0"),
      result(124, "", "timed out"),
    }) do
      results.lsof = failure
      rejected(ctx)
    end
  end)

  test("only editor-owned process IDs are excluded during preflight", function()
    local ctx = fixture()
    results.lsof = result(0, "p" .. vim.fn.getpid() .. "\0cnvim\0\nfcwd\0\nf3\0\n")
    cleanup.preflight(ctx)
    rejected(ctx, cleanup.cleanup)
    results.lsof = result(0, "p987654\0cnode\0\n")
    rejected(ctx)
    rejected(ctx, cleanup.cleanup)
  end)

  test("configured teardown permits services during preflight but never another editor", function()
    local ctx = fixture()
    project(ctx, { teardown = { "fake-teardown" }, verify = { "fake-verify" } })
    results.lsof = result(0, "p987654\0cnode\0\n")
    cleanup.preflight(ctx)
    rejected(ctx, cleanup.cleanup)
    assert(call_index("fake-teardown") and call_index("fake-verify"))
    results.lsof = result(0, "p987655\0cnvim\0\n")
    rejected(ctx)
    on_script = function(name)
      if name == "fake-teardown" then
        results.lsof = result(1)
      end
    end
    results.lsof = result(0, "p987654\0cnode\0\n")
    cleanup.cleanup(ctx)
    assert(not exists(ctx.path))
  end)

  test("lsof no-match exit status must not hide stderr errors", function()
    local ctx = fixture()
    results.lsof = result(1, "", "cannot examine directory")
    rejected(ctx)
  end)

  local function container(path, running, label)
    return {
      Id = "a1b2c3",
      Name = "/test-container",
      State = { Running = running },
      Mounts = label and {} or { { Type = "bind", Source = path, Destination = "/app" } },
      Config = { Labels = label and { [label] = path } or {} },
    }
  end

  test("running and stopped Docker containers with review bind mounts block deletion", function()
    for _, running in ipairs({ true, false }) do
      local ctx = fixture()
      docker_available = true
      results.docker = result(0, "a1b2c3\n")
      results.inspect = result(0, vim.json.encode({ container(ctx.path .. "/subdirectory", running) }))
      rejected(ctx)
      rejected(ctx, cleanup.cleanup)
      local _, ps_call = call_index("docker", "ps")
      assert(ps_call and table.concat(ps_call.args, " "):find("a"), "Docker probe did not include stopped containers")
    end
  end)

  test("Docker Compose working directories and config files match worktree boundaries", function()
    for _, label in ipairs({ "com.docker.compose.project.working_dir", "com.docker.compose.project.config_files" }) do
      local ctx = fixture()
      docker_available = true
      results.docker = result(0, "a1b2c3\n")
      local path = ctx.path
      if label:find("config_files", 1, true) then
        path = "/elsewhere/compose.yml," .. ctx.path .. "/compose.override.yml"
      end
      results.inspect = result(0, vim.json.encode({ container(path, false, label) }))
      rejected(ctx)
    end
    local ctx = fixture()
    docker_available = true
    results.docker = result(0, "a1b2c3\n")
    results.inspect = result(0, vim.json.encode({ container(ctx.path .. "-other", true) }))
    cleanup.preflight(ctx)
    cleanup.cleanup(ctx)
    assert(not exists(ctx.path))
    for _, call in ipairs(calls) do
      if call.args[1] == "docker" then
        assert(call.args[2] == "ps" or call.args[2] == "inspect", "Resource detection mutated Docker")
      end
    end
  end)

  test("Docker must succeed with well-formed inspection output when installed", function()
    for _, failure in ipairs({ "daemon", "timeout", "json", "shape", "inspect" }) do
      local ctx = fixture()
      docker_available = true
      results.docker = result(0, "a1b2c3\n")
      results.inspect = result(0, vim.json.encode({ container("/other", true) }))
      if failure == "daemon" then
        results.docker = result(1, "", "Cannot connect to daemon")
      elseif failure == "timeout" then
        results.docker = result(124, "", "timed out")
      elseif failure == "json" then
        results.inspect = result(0, "not json")
      elseif failure == "shape" then
        results.inspect = result(0, "{}")
      else
        results.inspect = result(1, "", "inspect denied")
      end
      rejected(ctx)
    end
  end)

  test("configured Docker teardown is followed by a fresh container check", function()
    local ctx = fixture()
    project(ctx, { teardown = { "fake-teardown" }, verify = { "fake-verify" } })
    docker_available = true
    results.docker = result(0, "a1b2c3\n")
    results.inspect = result(0, vim.json.encode({ container(ctx.path, true) }))
    cleanup.preflight(ctx)
    on_script = function(name)
      if name == "fake-teardown" then
        results.docker = result()
      end
    end
    cleanup.cleanup(ctx)
    assert(not exists(ctx.path))
  end)

  test("a failed worktree removal preserves the review branch", function()
    local ctx, repo = fixture()
    results.git_remove = result(1, "", "worktree removal failed")
    rejected(ctx, cleanup.cleanup)
    assert(git(repo, "rev-parse", ctx.branch) == ctx.head)
  end)

  test("metadata failure reports partial cleanup after branch and worktree removal", function()
    local ctx, repo = fixture()
    results.git_metadata = result(1, "", "cannot lock config")
    local success, failure = pcall(cleanup.cleanup, ctx)
    assert(not success and tostring(failure):find("metadata", 1, true))
    assert(not exists(ctx.path))
    assert(not git(repo, "for-each-ref", "--format=%(refname)", "refs/heads"):find(ctx.branch, 1, true))
    assert(git(repo, "config", "--get", "branch." .. ctx.branch .. ".diffview-pr") == ctx.pr_url)
  end)

  test("branch changes during removal survive compare-and-swap deletion", function()
    local ctx, repo, base = fixture()
    local changed = false
    before_command = function(args)
      if args[1] == "git" and vim.tbl_contains(args, "update-ref") and vim.tbl_contains(args, "-d") then
        changed = true
        git(repo, "update-ref", "refs/heads/" .. ctx.branch, base)
      end
    end
    local success, failure = pcall(cleanup.cleanup, ctx)
    assert(changed, "Cleanup never attempted atomic branch deletion")
    assert(not success and failure, "A concurrent branch change was reported as success")
    assert(not exists(ctx.path), "Fixture did not reach post-removal branch deletion")
    assert(git(repo, "rev-parse", ctx.branch) == base, "Concurrent branch update was discarded")
    assert(git(repo, "config", "--get", "branch." .. ctx.branch .. ".diffview-pr") == ctx.pr_url)
  end)
  assert(#failures == 0, table.concat(failures, "\n\n"))
end, debug.traceback)

-- Every fixture belongs only to this test process; force is for failed-test cleanup.
for _, tree in ipairs(fixtures) do
  if exists(tree.path) then
    system({ "git", "worktree", "unlock", tree.path }, { cwd = tree.repo, env = env }):wait()
    system({ "git", "worktree", "remove", "--force", tree.path }, { cwd = tree.repo, env = env }):wait()
  end
end
vim.fn.chdir(config)
vim.fn.delete(temp, "rf")
if not ok then
  error(err)
end
print(string.format("%d review cleanup tests passed", passed))
