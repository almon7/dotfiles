local M = {}
local uv = vim.uv
local active
local config_dir = vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(debug.getinfo(1, "S").source:sub(2))))

local function command(args, cwd, input)
  local result = vim
    .system(args, {
      cwd = cwd,
      stdin = input,
      text = true,
      timeout = 10000,
      env = { LC_ALL = "C", TZ = "UTC" },
    })
    :wait()
  if result.code ~= 0 then
    error(vim.trim(result.stderr or "") ~= "" and vim.trim(result.stderr) or table.concat(args, " ") .. " failed", 0)
  end
  return vim.trim(result.stdout or "")
end

local function read(path)
  local file = io.open(path, "r")
  if not file then
    return nil
  end
  local contents = file:read("*a")
  file:close()
  local ok, value = pcall(vim.json.decode, contents)
  if not ok or type(value) ~= "table" then
    error("Invalid review session record: " .. path, 0)
  end
  return value
end

local function write(path, value)
  local temporary = path .. ".tmp"
  local file = assert(io.open(temporary, "w"))
  assert(file:write(vim.json.encode(value)))
  assert(file:close())
  assert(uv.fs_rename(temporary, path))
end

local function stamp(pid)
  return command({ "ps", "-p", tostring(pid), "-o", "lstart=" })
end

local function alive(ctx)
  local ok, _, code = uv.kill(ctx.owner_pid, 0)
  if not ok then
    if code == "ESRCH" then
      return false
    end
    error("Cannot check review process " .. tostring(ctx.owner_pid), 0)
  end
  return stamp(ctx.owner_pid) == ctx.owner_start
end

local function tmux(ctx, args)
  return command(vim.list_extend({ "tmux", "-S", ctx.socket }, args))
end

local function registry(common, ref, optional)
  local result = vim
    .system({ "git", "--git-dir=" .. common, "rev-parse", "--verify", "--quiet", ref }, {
      text = true,
      timeout = 10000,
    })
    :wait()
  if optional and result.code == 1 then
    return nil
  end
  if result.code ~= 0 then
    error("Cannot read review reservation: " .. vim.trim(result.stderr or ""), 0)
  end
  local oid = vim.trim(result.stdout)
  local saved = vim.json.decode(command({ "git", "--git-dir=" .. common, "cat-file", "blob", oid }))
  if type(saved) ~= "table" or saved.common_dir ~= common or saved.registry ~= ref then
    error("Invalid review reservation: " .. ref, 0)
  end
  saved.revision_id = oid
  return saved
end

local function current(ctx)
  local saved = registry(ctx.common_dir, ctx.registry)
  if saved.token ~= ctx.token then
    error("Review session ownership changed; keeping " .. ctx.path, 0)
  end
  return saved
end

-- Git's compare-and-swap protects stale reclamation and owner handover from competing openers.
local function publish(ctx, previous)
  local saved = vim.deepcopy(ctx)
  saved.revision_id, saved.closing = nil, nil
  write(ctx.record, saved)
  local oid =
    command({ "git", "--git-dir=" .. ctx.common_dir, "hash-object", "-w", "--stdin" }, nil, vim.json.encode(saved))
  command({ "git", "--git-dir=" .. ctx.common_dir, "update-ref", ctx.registry, oid, previous or string.rep("0", #oid) })
  ctx.revision_id = oid
end

function M.path(pr)
  local path = vim.fs.joinpath(vim.fn.expand("~/reviews"), pr.identity, "pr-" .. pr.number)
  local suffix = {}
  while not uv.fs_realpath(path) do
    table.insert(suffix, 1, vim.fs.basename(path))
    path = vim.fs.dirname(path)
  end
  return vim.fs.joinpath(uv.fs_realpath(path), unpack(suffix))
end

local function remove_record(ctx)
  for _, name in ipairs({ "request.json", "request.json.tmp", "context.json.tmp", "context.json" }) do
    local path = ctx.state_dir .. "/" .. name
    if uv.fs_lstat(path) then
      assert(uv.fs_unlink(path))
    end
  end
  assert(uv.fs_rmdir(ctx.state_dir))
end

function M.release(ctx)
  local saved = current(ctx)
  command({ "git", "--git-dir=" .. saved.common_dir, "update-ref", "-d", saved.registry, saved.revision_id })
  remove_record(saved)
end

-- Reserving before fetching prevents another opener from updating an active review.
function M.reserve(repo, pr)
  local common = command({ "git", "rev-parse", "--path-format=absolute", "--git-common-dir" }, repo)
  common = assert(uv.fs_realpath(common))
  local path = vim.fs.normalize(M.path(pr))
  local parent = common .. "/diffview-reviews"
  vim.fn.mkdir(parent, "p", 448)
  local ref = "refs/diffview-reviews/" .. vim.fn.sha256(path)
  local existing = registry(common, ref, true)
  if existing then
    if existing.path ~= path then
      error("Review session record does not match " .. path, 0)
    end
    if alive(existing) then
      if not existing.pane then
        error("PR review is starting; try again shortly: " .. path, 0)
      end
      if tmux(existing, { "show-options", "-p", "-v", "-t", existing.pane, "@diffview_review" }) ~= existing.token then
        error("Review pane ownership changed; keeping " .. path, 0)
      end
      tmux(existing, { "select-window", "-t", existing.pane })
      tmux(existing, { "select-pane", "-t", existing.pane })
      return nil
    end
  end
  local token = vim.fn.sha256(tostring(uv.hrtime()) .. ":" .. tostring(uv.os_getpid()))
  local state_dir = parent .. "/" .. token
  assert(uv.fs_mkdir(state_dir, 448))
  local record = state_dir .. "/context.json"
  local ctx = {
    token = token,
    path = path,
    common_dir = common,
    branch = "review/pr-" .. pr.number,
    pr_url = pr.url,
    identity = pr.identity,
    head = pr.headRefOid,
    config_dir = assert(uv.fs_realpath(config_dir)),
    owner_pid = uv.os_getpid(),
    owner_start = stamp(uv.os_getpid()),
    socket = assert(vim.env.TMUX:match("^(.*),%d+,%d+$"), "Cannot identify tmux socket"),
    record = record,
    state_dir = state_dir,
    registry = ref,
    nvim = vim.v.progpath,
  }
  local ok, err = pcall(publish, ctx, existing and existing.revision_id)
  if not ok then
    remove_record(ctx)
    error("Review reservation changed; try again: " .. tostring(err), 0)
  end
  if existing then
    local cleaned, cleanup_error = pcall(remove_record, existing)
    if not cleaned then
      vim.notify(
        "Review reserved, but old session metadata could not be removed: " .. tostring(cleanup_error),
        vim.log.levels.WARN,
        { title = "Git view" }
      )
    end
  end
  return ctx
end

function M.prepare(ctx, revision)
  local saved = current(ctx)
  ctx.path = assert(uv.fs_realpath(ctx.path))
  ctx.revision = revision
  publish(ctx, saved.revision_id)
end

function M.start(record, owner_pid)
  local ctx = current(assert(read(record), "Review session record is missing"))
  if ctx.config_dir ~= uv.fs_realpath(config_dir) or ctx.record ~= record then
    error("Review configuration does not match the trusted launcher", 0)
  end
  ctx.owner_pid = assert(tonumber(owner_pid))
  ctx.owner_start = stamp(ctx.owner_pid)
  ctx.pane = assert(vim.env.TMUX_PANE)
  tmux(ctx, { "set-option", "-p", "-t", ctx.pane, "@diffview_review", ctx.token })
  publish(ctx, ctx.revision_id)
  active = ctx
  vim.cmd.cd(ctx.path)
  require("diffview").open({ "-C" .. ctx.path, ctx.revision, "--imply-local" })
end

local function owned_pids(ctx)
  local result = command({ "ps", "-A", "-o", "pid=,ppid=" })
  local owned = { [uv.os_getpid()] = true, [ctx.owner_pid] = true }
  local children, parents = {}, {}
  for line in result:gmatch("[^\n]+") do
    local pid, parent = line:match("^%s*(%d+)%s+(%d+)%s*$")
    if not pid then
      error("Cannot parse process ownership", 0)
    end
    children[#children + 1] = { tonumber(pid), tonumber(parent) }
    parents[tonumber(pid)] = tonumber(parent)
  end
  -- The Lua process may be an embedded child of Neovim's TUI process.
  local ancestor = uv.os_getpid()
  while ancestor ~= ctx.owner_pid do
    ancestor = parents[ancestor]
    if not ancestor or ancestor <= 1 then
      error("The review editor no longer belongs to its launcher", 0)
    end
    owned[ancestor] = true
  end
  -- Terminal jobs can contain user work; other editor children are checked again after exit.
  local terminals = {}
  for _, channel in ipairs(vim.api.nvim_list_chans()) do
    if channel.mode == "terminal" then
      terminals[vim.fn.jobpid(channel.id)] = true
    end
  end
  local changed = true
  while changed do
    changed = false
    for _, pair in ipairs(children) do
      if terminals[pair[2]] then
        terminals[pair[1]] = true
      end
      if owned[pair[2]] and pair[2] ~= ctx.owner_pid and not terminals[pair[1]] and not owned[pair[1]] then
        owned[pair[1]], changed = true, true
      end
    end
  end
  return vim.tbl_keys(owned)
end

local function helper(ctx, action, callback)
  vim.system({ ctx.nvim, "-l", ctx.config_dir .. "/review-session.lua", action, ctx.record }, {
    cwd = ctx.common_dir,
    text = true,
    timeout = 60000,
  }, vim.schedule_wrap(callback))
end

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = "Git view" })
end

function M.close()
  local view = package.loaded["diffview.lib"] and require("diffview.lib").get_current_view()
  if not active or (view and uv.fs_realpath(view.adapter.ctx.toplevel) ~= active.path) then
    if view then
      require("diffview").close()
    else
      notify("No review to close")
    end
    return
  end
  local ctx = active
  if ctx.closing then
    return
  end
  for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[buffer].modified then
      notify(
        "Unsaved buffer; keeping review open: "
          .. (vim.api.nvim_buf_get_name(buffer) ~= "" and vim.api.nvim_buf_get_name(buffer) or "[No Name]"),
        vim.log.levels.WARN
      )
      return
    end
  end
  local ok, err = pcall(function()
    local saved = current(ctx)
    ctx.owned_pids = owned_pids(ctx)
    publish(ctx, saved.revision_id)
  end)
  if not ok then
    notify(tostring(err), vim.log.levels.ERROR)
    return
  end
  ctx.closing = true
  notify("Checking review before cleanup…")
  helper(ctx, "preflight", function(result)
    ctx.closing = nil
    if result.code ~= 0 then
      local detail = vim.trim(result.stderr or "")
      if detail == "" then
        detail = vim.trim(result.stdout or "")
      end
      notify(
        detail ~= "" and detail or "Review preflight failed or timed out; keeping the worktree",
        vim.log.levels.WARN
      )
      return
    end
    -- Editing can continue while probes run, so recheck every buffer before quitting.
    for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
      if vim.bo[buffer].modified then
        notify("A buffer changed during preflight; keeping review open", vim.log.levels.WARN)
        return
      end
    end
    for _, client in ipairs(vim.lsp.get_clients()) do
      client.exit_timeout = 5000
    end
    local request = ctx.state_dir .. "/request.json"
    local quit_ok, quit_err = pcall(function()
      current(ctx)
      write(request, { token = ctx.token })
      vim.cmd("qall")
    end)
    -- A successful qall never returns. A cancelled/failed quit must not authorise a later :qa.
    uv.fs_unlink(request)
    if not quit_ok then
      notify("Review remains open: " .. tostring(quit_err), vim.log.levels.WARN)
    end
  end)
end

function M.run(action, record)
  local ctx = current(assert(read(record), "Review session record is missing"))
  if ctx.record ~= record or ctx.config_dir ~= uv.fs_realpath(config_dir) then
    error("Review session does not match its launcher", 0)
  end
  if action == "preflight" then
    require("config.review_cleanup").preflight(ctx)
  elseif action == "cleanup" then
    local request = read(ctx.state_dir .. "/request.json")
    if not request then
      return
    end
    if request.token ~= ctx.token then
      error("Cleanup request does not match the review session", 0)
    end
    assert(uv.fs_unlink(ctx.state_dir .. "/request.json"))
    require("config.review_cleanup").cleanup(ctx)
  elseif action == "release" then
    M.release(ctx)
  else
    error("Unknown review action: " .. tostring(action), 0)
  end
end

return M
