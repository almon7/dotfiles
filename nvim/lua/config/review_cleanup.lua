local M = {}
local repository = require("config.git_repository")
local uv = vim.uv

local function fail(message)
  error(message, 0)
end

local function inside(path, directory)
  return path == directory
    or (directory == "/" and path:sub(1, 1) == "/")
    or path:sub(1, #directory + 1) == directory .. "/"
end

local function result(cwd, args, timeout)
  local ok, value = pcall(function()
    return vim.system(args, { cwd = cwd, env = { GIT_OPTIONAL_LOCKS = "0" }, timeout = timeout or 10000 }):wait()
  end)
  if not ok then
    fail(tostring(value))
  end
  return value
end

local function run(cwd, args, timeout)
  local value = result(cwd, args, timeout)
  if value.code ~= 0 then
    local detail = vim.trim(value.stderr or "")
    fail(args[1] .. " failed: " .. (detail ~= "" and detail or ("exit " .. value.code)))
  end
  return value.stdout or ""
end

local function git(ctx, args)
  return run(ctx.common_dir, vim.list_extend({ "git", "-C", ctx.path }, args))
end

local function shared_git(ctx, args)
  return run(ctx.common_dir, vim.list_extend({ "git", "--git-dir=" .. ctx.common_dir }, args))
end

local function fields(value)
  local values = {}
  for field in value:gmatch("([^%z]+)") do
    values[#values + 1] = field
  end
  return values
end

local function realpath(path, label)
  if type(path) ~= "string" or path:sub(1, 1) ~= "/" then
    fail(label .. " must be an absolute path.")
  end
  local resolved = uv.fs_realpath(path)
  if not resolved then
    fail(label .. " does not exist: " .. path)
  end
  return resolved
end

local function stat(path)
  local value, message, code = uv.fs_lstat(path)
  if not value and code ~= "ENOENT" then
    fail("Cannot inspect path: " .. tostring(message))
  end
  return value
end

local function command(value, name)
  if value == nil then
    return
  end
  if type(value) ~= "table" or #value == 0 then
    fail(name .. " must be a non-empty argument array.")
  end
  for _, arg in ipairs(value) do
    if type(arg) ~= "string" or arg:find("%z") then
      fail(name .. " must contain only string arguments.")
    end
  end
  return value
end

local function context(ctx)
  ctx = vim.deepcopy(ctx)
  ctx.path = realpath(ctx.path, "Review worktree")
  ctx.common_dir = realpath(ctx.common_dir, "Shared Git directory")
  ctx.config_dir = realpath(ctx.config_dir, "Trusted Neovim configuration")
  if inside(ctx.common_dir, ctx.path) or inside(ctx.config_dir, ctx.path) then
    fail("The shared Git directory and trusted configuration must be outside the review worktree.")
  end
  if type(ctx.branch) ~= "string" or not ctx.branch:match("^review/pr%-%d+$") then
    fail("Invalid managed review branch.")
  end
  if type(ctx.head) ~= "string" or not ctx.head:match("^%x+$") then
    fail("Invalid recorded review commit.")
  end
  if type(ctx.identity) ~= "string" or type(ctx.pr_url) ~= "string" then
    fail("Missing managed review identity.")
  end
  local repository, number = ctx.pr_url:match("^https://([^/]+/[^/]+/[^/]+)/pull/(%d+)/?$")
  if repository ~= ctx.identity or ctx.branch ~= "review/pr-" .. tostring(number) then
    fail("The review identity and branch do not match the recorded PR URL.")
  end
  local ok, projects = pcall(dofile, ctx.config_dir .. "/lua/config/review_projects.lua")
  if not ok or type(projects) ~= "table" then
    fail("Cannot load trusted review settings: " .. tostring(projects))
  end
  local recipe = projects[ctx.identity] or {}
  if type(recipe) ~= "table" then
    fail("Review settings for " .. ctx.identity .. " must be a table.")
  end
  command(recipe.teardown, "teardown")
  command(recipe.verify, "verify")
  if (recipe.teardown ~= nil) ~= (recipe.verify ~= nil) then
    fail("Configured teardown and verify commands must be provided together.")
  end
  if recipe.disposable_paths ~= nil and type(recipe.disposable_paths) ~= "table" then
    fail("disposable_paths must be an array of relative paths.")
  end
  return ctx, recipe
end

local function worktrees(ctx)
  local entries, entry = {}, {}
  local output = shared_git(ctx, { "worktree", "list", "--porcelain", "-z" })
  for field in (output .. "\0"):gmatch("([^%z]*)%z") do
    if field == "" then
      if entry.worktree then
        entries[#entries + 1] = entry
        entry = {}
      end
    else
      local key, value = field:match("^(%S+)%s?(.*)$")
      entry[key] = value
    end
  end
  return entries
end

local function identity(ctx)
  local found
  for _, entry in ipairs(worktrees(ctx)) do
    if uv.fs_realpath(entry.worktree) == ctx.path then
      found = entry
      break
    end
  end
  if not found or found.branch ~= "refs/heads/" .. ctx.branch or found.HEAD ~= ctx.head then
    fail("The review worktree, branch or commit changed; keep the worktree.")
  end
  if found.locked ~= nil or found.prunable ~= nil then
    fail("The review worktree is locked or prunable; keep the worktree.")
  end
  local common = vim.trim(git(ctx, { "rev-parse", "--path-format=absolute", "--git-common-dir" }))
  local directory = vim.trim(git(ctx, { "rev-parse", "--absolute-git-dir" }))
  directory = realpath(directory, "Review Git directory")
  if uv.fs_realpath(common) ~= ctx.common_dir or not inside(directory, ctx.common_dir .. "/worktrees") then
    fail("The directory is not a linked worktree of the recorded repository.")
  end
  local url = vim.trim(shared_git(ctx, { "config", "--local", "--get", "branch." .. ctx.branch .. ".diffview-pr" }))
  if url ~= ctx.pr_url then
    fail("The review branch no longer belongs to the recorded PR.")
  end
  local matching_remote = false
  for remote in shared_git(ctx, { "remote" }):gmatch("[^\r\n]+") do
    local remote_url = vim.trim(shared_git(ctx, { "config", "--get", "remote." .. remote .. ".url" }))
    matching_remote = matching_remote or repository(remote_url) == ctx.identity:lower()
  end
  if not matching_remote then
    fail("No configured remote matches the recorded review repository.")
  end
  for _, name in ipairs({
    "MERGE_HEAD",
    "CHERRY_PICK_HEAD",
    "REVERT_HEAD",
    "REBASE_HEAD",
    "BISECT_LOG",
    "BISECT_START",
    "rebase-merge",
    "rebase-apply",
    "sequencer",
    "index.lock",
    "HEAD.lock",
    "config.worktree.lock",
  }) do
    if stat(directory .. "/" .. name) then
      fail("Review Git operation or lock remains: " .. name)
    end
  end
  for _, name in ipairs({ "config.lock", "packed-refs.lock", "shallow.lock", "refs/heads/" .. ctx.branch .. ".lock" }) do
    if stat(ctx.common_dir .. "/" .. name) then
      fail("Shared Git lock remains: " .. name)
    end
  end
end

local function nested_repositories(path, root)
  local scan, err = uv.fs_scandir(path)
  if not scan then
    fail("Cannot inspect review directory: " .. tostring(err))
  end
  local entries = {}
  while true do
    local name, kind = uv.fs_scandir_next(scan)
    if not name then
      if kind then
        fail("Cannot inspect review directory: " .. tostring(kind))
      end
      break
    end
    entries[name] = kind or (stat(path .. "/" .. name) or {}).type
  end
  if
    path ~= root
    and (
      entries[".git"]
      or (entries.HEAD and entries.config and entries.objects == "directory" and entries.refs == "directory")
    )
  then
    fail("Nested Git repository remains: " .. path)
  end
  for name, kind in pairs(entries) do
    if kind == "directory" and name ~= ".git" then
      nested_repositories(path .. "/" .. name, root)
    end
  end
end

local function disposable_paths(ctx, recipe, tracked)
  local paths = {}
  -- Filesystem identity also catches case aliases and hardlinks that Git's path strings cannot.
  local tracked_objects, visited = {}, {}
  if #(recipe.disposable_paths or {}) > 0 then
    for _, file in ipairs(tracked) do
      local path = file
      while path ~= "." and path ~= "" and not visited[path] do
        visited[path] = true
        local entry = stat(ctx.path .. "/" .. path)
        if entry then
          tracked_objects[entry.dev .. ":" .. entry.ino] = file
        end
        path = vim.fs.dirname(path)
      end
    end
  end
  for _, value in ipairs(recipe.disposable_paths or {}) do
    if type(value) ~= "string" or value == "" or value:sub(1, 1) == "/" or value:find("[%z*?%[%]]") then
      fail("Disposable paths must be literal relative paths.")
    end
    value = value:gsub("/+$", "")
    local current = ctx.path
    local parts = vim.split(value, "/", { plain = true })
    for index, part in ipairs(parts) do
      if part == "" or part == "." or part == ".." or part:lower() == ".git" then
        fail("Unsafe disposable path: " .. value)
      end
      current = current .. "/" .. part
      local entry = stat(current)
      if index < #parts and entry and entry.type ~= "directory" then
        fail("Disposable path has a symlink or non-directory ancestor: " .. value)
      end
    end
    local target = stat(current)
    if target and tracked_objects[target.dev .. ":" .. target.ino] then
      fail("Disposable path aliases a tracked file or directory: " .. value)
    end
    for _, file in ipairs(tracked) do
      if inside(file, value) then
        fail("Disposable path contains a tracked file: " .. file)
      end
    end
    paths[#paths + 1] = value
  end
  return paths
end

local function files(ctx, recipe)
  for _, entry in ipairs(fields(git(ctx, { "ls-files", "-v", "-z" }))) do
    local flag = entry:sub(1, 1)
    if flag == "S" or flag:match("[a-z]") then
      fail("Index flags can hide local changes; clear assume-unchanged/skip-worktree before cleanup: " .. entry:sub(3))
    end
  end
  local tracked = {}
  for _, entry in ipairs(fields(git(ctx, { "ls-files", "--stage", "-z" }))) do
    local mode, file = entry:match("^(%d+) [^\t]+\t(.*)$")
    if not file then
      fail("Cannot parse the review index.")
    end
    if mode == "160000" then
      fail("The review worktree contains a submodule: " .. file)
    end
    tracked[#tracked + 1] = file
  end
  local paths = disposable_paths(ctx, recipe, tracked)
  local status = git(ctx, { "status", "--porcelain=v1", "-z", "--untracked-files=all" })
  for _, entry in ipairs(fields(status)) do
    if entry:sub(1, 2) ~= "??" then
      fail("The review worktree has tracked changes; keep the worktree.")
    end
  end
  local extras = fields(git(ctx, { "ls-files", "--others", "--exclude-standard", "-z" }))
  vim.list_extend(extras, fields(git(ctx, { "ls-files", "--others", "--ignored", "--exclude-standard", "-z" })))
  for _, file in ipairs(extras) do
    local allowed = false
    for _, path in ipairs(paths) do
      if inside(file, path) then
        allowed = true
        break
      end
    end
    if not allowed then
      fail("Unlisted extra file remains: " .. file)
    end
  end
  nested_repositories(ctx.path, ctx.path)
  return paths
end

local function processes(ctx, preflight, teardown)
  if vim.fn.executable("lsof") ~= 1 then
    fail("Cannot check review processes: lsof is not installed.")
  end
  local value = result(ctx.common_dir, { "lsof", "-nP", "+c", "0", "-F0pc", "+D", ctx.path })
  if vim.trim(value.stderr or "") ~= "" or (value.code ~= 0 and value.code ~= 1) then
    local detail = vim.trim(value.stderr or "")
    fail("Cannot check review processes: " .. (detail ~= "" and detail or ("exit " .. value.code)))
  end
  local owned = {}
  if preflight then
    for _, pid in ipairs(ctx.owned_pids or {}) do
      if type(pid) ~= "number" or pid <= 0 or pid % 1 ~= 0 then
        fail("Invalid owned process ID.")
      end
      owned[pid] = true
    end
  end
  local pid, seen, named = nil, false, true
  for _, field in ipairs(fields(value.stdout or "")) do
    field = field:gsub("^[\r\n]+", "")
    if field:sub(1, 1) == "p" then
      if not named then
        fail("Cannot parse review process inspection output.")
      end
      pid = tonumber(field:sub(2))
      if not pid or pid <= 0 or pid % 1 ~= 0 then
        fail("Cannot parse review process inspection output.")
      end
      seen, named = true, false
    elseif field:sub(1, 1) == "c" then
      if not pid or named or #field == 1 then
        fail("Cannot parse review process inspection output.")
      end
      named = true
      local name = field:sub(2)
      if not owned[pid] and (not (preflight and teardown) or name:match("nvim")) then
        fail("Process still uses the review worktree: " .. name .. " (PID " .. pid .. ")")
      end
    elseif field:sub(1, 1) == "f" then
      if not pid or not named or #field == 1 then
        fail("Cannot parse review process inspection output.")
      end
    elseif field ~= "" then
      fail("Cannot parse review process inspection output.")
    end
  end
  if not named or (value.code == 0 and not seen) then
    fail("Cannot parse review process inspection output.")
  end
end

local function overlaps(path, root)
  if type(path) ~= "string" or path:sub(1, 1) ~= "/" then
    return false
  end
  path = uv.fs_realpath(path) or vim.fs.normalize(path)
  return inside(path, root) or inside(root, path)
end

local function containers(ctx, preflight, teardown)
  if vim.fn.executable("docker") ~= 1 then
    return
  end
  local listed = run(ctx.common_dir, { "docker", "ps", "-aq" })
  local ids = {}
  for id in listed:gmatch("%S+") do
    if not id:match("^%x+$") then
      fail("Cannot parse Docker container list.")
    end
    ids[#ids + 1] = id
  end
  if #ids == 0 then
    return
  end
  local output = run(ctx.common_dir, vim.list_extend({ "docker", "inspect" }, ids))
  local ok, inspected = pcall(vim.json.decode, output)
  if not ok or type(inspected) ~= "table" or #inspected ~= #ids then
    fail("Cannot parse Docker container inspection.")
  end
  for _, container in ipairs(inspected) do
    if type(container) ~= "table" or type(container.Mounts) ~= "table" or type(container.Config) ~= "table" then
      fail("Incomplete Docker container inspection.")
    end
    local related = false
    for _, mount in ipairs(container.Mounts) do
      if type(mount) ~= "table" or type(mount.Type) ~= "string" then
        fail("Cannot parse Docker container mounts.")
      end
      if mount.Type == "bind" and (type(mount.Source) ~= "string" or mount.Source:sub(1, 1) ~= "/") then
        fail("Cannot parse Docker bind mount source.")
      end
      if mount.Type == "bind" and overlaps(mount.Source, ctx.path) then
        related = true
      end
    end
    local labels = container.Config.Labels
    if labels ~= nil and labels ~= vim.NIL then
      if type(labels) ~= "table" then
        fail("Cannot parse Docker container labels.")
      end
      for _, key in ipairs({ "com.docker.compose.project.working_dir", "com.docker.compose.project.config_files" }) do
        if labels[key] ~= nil and type(labels[key]) ~= "string" then
          fail("Cannot parse Docker Compose labels.")
        end
      end
      related = related or overlaps(labels["com.docker.compose.project.working_dir"], ctx.path)
      for path in (labels["com.docker.compose.project.config_files"] or ""):gmatch("[^,]+") do
        related = related or overlaps(path, ctx.path)
      end
    end
    if related and not (preflight and teardown) then
      fail("Container still belongs to the review worktree: " .. tostring(container.Name or container.Id))
    end
  end
end

local function resources(ctx, recipe, preflight)
  processes(ctx, preflight, recipe.teardown)
  containers(ctx, preflight, recipe.teardown)
end

function M.preflight(value)
  local ctx, recipe = context(value)
  identity(ctx)
  files(ctx, recipe)
  resources(ctx, recipe, true)
  return true
end

function M.cleanup(value)
  local ctx, recipe = context(value)
  identity(ctx)
  files(ctx, recipe)
  if recipe.teardown then
    run(ctx.path, recipe.teardown, 60000)
  end
  if recipe.verify then
    run(ctx.path, recipe.verify, 60000)
  end
  resources(ctx, recipe, false)
  identity(ctx)
  local paths = files(ctx, recipe)
  for _, path in ipairs(paths) do
    local absolute = ctx.path .. "/" .. path
    if stat(absolute) then
      vim.fs.rm(absolute, { recursive = true })
    end
  end
  identity(ctx)
  files(ctx, {})
  shared_git(ctx, { "worktree", "remove", ctx.path })
  for _, entry in ipairs(worktrees(ctx)) do
    if entry.branch == "refs/heads/" .. ctx.branch then
      fail("Worktree removed, but its branch is now checked out elsewhere; retained " .. ctx.branch .. ".")
    end
  end
  local deleted, branch_error = pcall(shared_git, ctx, { "update-ref", "-d", "refs/heads/" .. ctx.branch, ctx.head })
  if not deleted then
    fail("Worktree removed, but review branch was retained: " .. tostring(branch_error))
  end
  local cleared = result(ctx.common_dir, {
    "git",
    "--git-dir=" .. ctx.common_dir,
    "config",
    "--local",
    "--fixed-value",
    "--unset-all",
    "branch." .. ctx.branch .. ".diffview-pr",
    ctx.pr_url,
  })
  if cleared.code ~= 0 and cleared.code ~= 5 then
    fail("Worktree and branch removed, but PR metadata cleanup failed: " .. vim.trim(cleared.stderr or ""))
  end
  return true
end

return M
