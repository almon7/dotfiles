local M = {}

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = "Diffview" })
end

-- Suspend only this operation while Git/GitHub run; resume on Neovim's main loop.
local function async(fn)
  local thread = coroutine.create(function()
    local ok, err = pcall(fn)
    if not ok then
      notify(tostring(err), vim.log.levels.ERROR)
    end
  end)
  coroutine.resume(thread)
end

local function run(root, args, optional)
  local thread = coroutine.running()
  vim.system(
    args,
    { cwd = root, text = true, timeout = 60000 },
    vim.schedule_wrap(function(result)
      coroutine.resume(thread, result)
    end)
  )
  local result = coroutine.yield()
  if result.code ~= 0 and not optional then
    error(vim.trim(result.stderr or "") ~= "" and vim.trim(result.stderr) or (args[1] .. " failed"), 0)
  end
  return vim.trim(result.stdout or ""), result.code
end

local function git(root, args, optional)
  return run(root, vim.list_extend({ "git" }, args), optional)
end

local function input(opts)
  local thread = coroutine.running()
  vim.ui.input(
    opts,
    vim.schedule_wrap(function(value)
      coroutine.resume(thread, value)
    end)
  )
  return coroutine.yield()
end

local function select_pr(repo)
  local json = run(repo, {
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
  })
  local prs = vim.json.decode(json)
  if #prs == 0 then
    notify("No open PRs.")
  end
  local manual = { title = "Enter PR number or URL…" }
  prs[#prs + 1] = manual
  local thread = coroutine.running()
  vim.ui.select(
    prs,
    {
      prompt = "GitHub PRs (newest 50 open): ",
      format_item = function(pr)
        if pr == manual then
          return pr.title
        end
        return string.format(
          "#%d %s — @%s%s",
          pr.number,
          pr.title,
          type(pr.author) == "table" and pr.author.login or "unknown",
          pr.isDraft and " [draft]" or ""
        )
      end,
    },
    vim.schedule_wrap(function(choice)
      coroutine.resume(thread, choice)
    end)
  )
  local choice = coroutine.yield()
  if choice == manual then
    return input({ prompt = "GitHub PR number or URL (blank: current branch): " })
  end
  return choice and choice.url
end

local function root()
  local view = package.loaded["diffview.lib"] and require("diffview.lib").get_current_view()
  local path = view and view.adapter.ctx.toplevel or (vim.bo.buftype == "" and vim.api.nvim_buf_get_name(0) or "")
  path = path ~= "" and path or vim.fn.getcwd()
  local found = vim.fs.root(vim.uv.fs_realpath(path) or path, ".git")
  if not found then
    notify("Open a file or directory inside a Git repository.", vim.log.levels.WARN)
  end
  return found
end

local function open_diff(repo, revision, local_files)
  local args = { "-C" .. repo }
  if revision then
    args[#args + 1] = revision
  end
  if local_files then
    args[#args + 1] = "--imply-local"
  end
  require("diffview").open(args)
end

-- Match repository identity without changing the user's configured transport.
local function repository(url)
  url = url:gsub("/+$", ""):gsub("%.git$", "")
  local host, owner, name = url:match("^%w+://([^/]+)/([^/]+)/([^/]+)$")
  if not host then
    host, owner, name = url:match("^[^@]+@([^:]+):([^/]+)/([^/]+)$")
  end
  if host then
    host = host:gsub("^.*@", ""):gsub(":%d+$", "")
    return (host .. "/" .. owner .. "/" .. name):lower()
  end
end

local function remote_for(repo, url)
  local identity = repository(url)
  for remote in git(repo, { "remote" }):gmatch("[^\n]+") do
    local configured = git(repo, { "config", "--get", "remote." .. remote .. ".url" })
    if identity and repository(configured) == identity then
      return remote
    end
  end
  error("The PR's repository does not match a remote in " .. repo .. ". Open that repository first.", 0)
end

local function remembered_pr(repo)
  local branch = git(repo, { "symbolic-ref", "--quiet", "--short", "HEAD" }, true)
  if branch ~= "" then
    return (git(repo, { "config", "--get", "branch." .. branch .. ".diffview-pr" }, true))
  end
  return ""
end

local function github_pr(repo, target, fields, optional)
  if target == "" then
    target = remembered_pr(repo)
  end
  local args = { "gh", "pr", "view" }
  if target ~= "" then
    args[#args + 1] = target
  end
  vim.list_extend(args, { "--json", fields })
  local json, code = run(repo, args, optional)
  if code == 0 then
    return vim.json.decode(json)
  end
end

local function pr_metadata(repo, target)
  local pr = github_pr(repo, target, "number,url,baseRefName,baseRefOid,headRefOid")
  local host, owner, name, number = pr.url:match("^https://([%w.-]+)/([%w_.-]+)/([%w_.-]+)/pull/(%d+)/?$")
  if
    not host
    or tonumber(number) ~= pr.number
    or not pr.baseRefOid:match("^%x+$")
    or not pr.headRefOid:match("^%x+$")
  then
    error("GitHub returned incomplete PR metadata.", 0)
  end
  pr.identity = host .. "/" .. owner .. "/" .. name
  pr.name = name
  pr.remote = remote_for(repo, "https://" .. pr.identity)
  return pr
end

local function fetch_pr(repo, pr)
  notify("Fetching " .. pr.identity .. "#" .. pr.number .. "…")
  local ref = "refs/diffview/" .. pr.identity .. "/pr-" .. pr.number
  git(repo, {
    "fetch",
    "--no-tags",
    "--no-write-fetch-head",
    pr.remote,
    "+" .. pr.baseRefOid .. ":" .. ref .. "/base",
    "+refs/pull/" .. pr.number .. "/head:" .. ref .. "/head",
  })
  if git(repo, { "rev-parse", ref .. "/head" }) ~= pr.headRefOid then
    error("The PR changed while fetching. Open the PR again to review its latest version.", 0)
  end
  local base = git(repo, { "merge-base", pr.baseRefOid, pr.headRefOid })
  return base .. ".." .. pr.headRefOid
end

local function worktree(repo, pr)
  local path = vim.fs.joinpath(vim.fn.expand("~/reviews"), pr.identity, "pr-" .. pr.number)
  local branch = "review/pr-" .. pr.number
  local stat = vim.uv.fs_lstat(path)
  if stat then
    if stat.type ~= "directory" then
      error("Worktree path is already occupied: " .. path, 0)
    end
    local top, code = git(path, { "rev-parse", "--show-toplevel" }, true)
    if code ~= 0 or vim.uv.fs_realpath(top) ~= vim.uv.fs_realpath(path) then
      error("Worktree path is already occupied: " .. path, 0)
    end
    local common = { "rev-parse", "--path-format=absolute", "--git-common-dir" }
    local repo_common = git(repo, common)
    local worktree_common = git(path, common)
    if
      vim.uv.fs_realpath(repo_common) ~= vim.uv.fs_realpath(worktree_common)
      or git(path, { "symbolic-ref", "--quiet", "HEAD" }, true) ~= "refs/heads/" .. branch
    then
      error("Existing directory is not this PR's review worktree: " .. path, 0)
    end
    if git(path, { "status", "--porcelain" }) ~= "" then
      error("PR worktree has local changes; reconcile them before reopening: " .. path, 0)
    end
    if git(path, { "rev-parse", "HEAD" }) ~= pr.headRefOid then
      local _, ancestor = git(path, { "merge-base", "--is-ancestor", "HEAD", pr.headRefOid }, true)
      if ancestor ~= 0 then
        error("PR worktree has local commits or diverged history; reconcile it before reopening: " .. path, 0)
      end
      git(path, { "merge", "--ff-only", "--no-edit", "--no-overwrite-ignore", pr.headRefOid })
    end
  else
    local ref = "refs/heads/" .. branch
    local _, exists = git(repo, { "show-ref", "--verify", "--quiet", ref }, true)
    if exists == 0 then
      local remembered = git(repo, { "config", "--get", "branch." .. branch .. ".diffview-pr" }, true)
      if remembered ~= pr.url then
        error("Review branch already exists and is not registered for this PR: " .. branch, 0)
      end
      local _, ancestor = git(repo, { "merge-base", "--is-ancestor", ref, pr.headRefOid }, true)
      if ancestor ~= 0 then
        error("Review branch has local commits or diverged history; reconcile it before reopening: " .. branch, 0)
      end
    end
    vim.fn.mkdir(vim.fs.dirname(path), "p")
    if exists == 0 then
      git(repo, { "worktree", "add", path, branch })
      git(path, { "merge", "--ff-only", "--no-edit", "--no-overwrite-ignore", pr.headRefOid })
    else
      git(repo, { "worktree", "add", "-b", branch, path, pr.headRefOid })
    end
  end
  git(repo, { "config", "branch." .. branch .. ".diffview-pr", pr.url })
  return path
end

function M.open(staged)
  local repo = root()
  if repo then
    open_diff(repo, staged and "--cached" or nil)
  end
end

function M.history(current_file)
  local repo = root()
  if not repo then
    return
  end
  local args = { "-C" .. repo }
  if current_file then
    local file = vim.api.nvim_buf_get_name(0)
    if vim.bo.buftype ~= "" or file == "" then
      notify("Open the actual file with gf before viewing its history.", vim.log.levels.WARN)
      return
    end
    args[#args + 1] = file
  end
  require("diffview").file_history(nil, args)
end

function M.branch()
  local repo = root()
  if not repo then
    return
  end
  async(function()
    local default = git(repo, { "symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD" }, true)
    if vim.fn.executable("gh") == 1 then
      local pr = github_pr(repo, "", "url,baseRefName", true)
      if pr then
        local repo_url = pr.url:match("^(https://.-)/pull/%d+$")
        if repo_url then
          local ok, remote = pcall(remote_for, repo, repo_url)
          if ok then
            default = remote .. "/" .. pr.baseRefName
          end
        end
      end
    end
    local base = input({ prompt = "Review branch against base: ", default = default })
    if not base or vim.trim(base) == "" then
      return
    end
    base = vim.trim(base)
    for remote in git(repo, { "remote" }):gmatch("[^\n]+") do
      local prefix = remote .. "/"
      if vim.startswith(base, prefix) then
        local branch = base:sub(#prefix + 1)
        git(repo, { "check-ref-format", "refs/heads/" .. branch })
        git(repo, { "fetch", "--no-tags", remote, "+refs/heads/" .. branch .. ":refs/remotes/" .. base })
        break
      end
    end
    local sha = git(repo, { "rev-parse", "--verify", "--end-of-options", base .. "^{commit}" })
    local head = git(repo, { "rev-parse", "HEAD" })
    open_diff(repo, git(repo, { "merge-base", sha, head }) .. ".." .. head, true)
  end)
end

function M.pr(in_worktree)
  local repo = root()
  if not repo then
    return
  end
  if vim.fn.executable("gh") ~= 1 then
    notify(
      "GitHub CLI is missing. Rerun ./nvim/install.sh, then authenticate with gh auth login.",
      vim.log.levels.ERROR
    )
    return
  end
  if in_worktree and (not vim.env.TMUX or not vim.env.TMUX_PANE or vim.fn.executable("tmux") ~= 1) then
    notify("Run Neovim inside tmux to open a PR worktree in a new window.", vim.log.levels.WARN)
    return
  end
  local pane = vim.env.TMUX_PANE
  async(function()
    local target = select_pr(repo)
    if target == nil then
      return
    end
    target = vim.trim(target):gsub("^#", "")
    if
      target ~= ""
      and not target:match("^%d+$")
      and not target:match("^https://[%w.-]+/[%w_.-]+/[%w_.-]+/pull/%d+/?$")
    then
      error("Enter a PR number or a full GitHub PR URL.", 0)
    end
    local session = in_worktree and run(repo, { "tmux", "display-message", "-p", "-t", pane, "#{session_id}" })
    local pr = pr_metadata(repo, target)
    local revision = fetch_pr(repo, pr)
    if not in_worktree then
      open_diff(repo, revision)
      return
    end
    local path = worktree(repo, pr)
    local startup = string.format("lua require('diffview').open({%q, %q, %q})", "-C" .. path, revision, "--imply-local")
    run(repo, {
      "tmux",
      "new-window",
      "-t",
      session .. ":",
      "-n",
      pr.name .. "/pr-" .. pr.number,
      "-c",
      path,
      "--",
      vim.v.progpath,
      "-c",
      startup,
    })
    notify("Opened PR worktree: " .. path)
  end)
end

return M
