-- GitHub threads are decorations on the reviewed code, never source-buffer text.
local M = {}
local api = vim.api
local states = {}
local processes = {}
local namespace = api.nvim_create_namespace("GitHubReviewComments")
local config_dir = vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(debug.getinfo(1, "S").source:sub(2))))

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = "GitHub PR" })
end

local function run(args, options, callback)
  local process
  process = vim.system(args, options, function(result)
    processes[process] = nil
    callback(result)
  end)
  processes[process] = true
  return process
end

function M.context(repo, url, revision)
  local base, head = revision:match("^(%x+)%.%.(%x+)$")
  assert(base and head, "GitHub discussion needs an exact review revision")
  local python = vim.fn.exepath("python3")
  return {
    repo = repo,
    url = url,
    base = base,
    head = head,
    python = python ~= "" and python or "python3",
    reader = config_dir .. "/github-review/fetch.py",
  }
end

function M.hunk_extension()
  return config_dir .. "/github-review/hunk-pr"
end

local function valid(state)
  return states[state.view] == state and api.nvim_tabpage_is_valid(state.view.tabpage)
end

local function current_state()
  local lib = package.loaded["diffview.lib"]
  local state = lib and states[lib.get_current_view()]
  if not state then
    notify("Open a GitHub PR review with Space g v p, w or r first.")
  end
  return state
end

local function cancel_lookups(state)
  state.display_generation = state.display_generation + 1
  for _, process in ipairs(state.lookups) do
    process:kill(15)
  end
  state.lookups = {}
  for _, prepared in pairs(state.windows) do
    if api.nvim_buf_is_valid(prepared.buf) then
      api.nvim_buf_clear_namespace(prepared.buf, prepared.namespace, 0, -1)
    end
  end
  state.windows = {}
end

local function body_lines(item)
  local lines = {}
  for index, comment in ipairs(item.comments) do
    if index > 1 then
      lines[#lines + 1] = ""
    end
    local label = index == 1 and (item.isResolved and " [resolved]" or "") or " [reply]"
    lines[#lines + 1] = "GitHub @" .. comment.author .. label
    for _, line in ipairs(vim.split(comment.body:gsub("\r\n", "\n"), "\n", { plain = true })) do
      lines[#lines + 1] = line:gsub("\t", "    ")
    end
  end
  lines[#lines + 1] = ""
  return lines
end

-- Virtual lines do not obey 'wrap'; split by displayed cells, keeping UTF-8 intact.
local function wrap_lines(lines, width)
  local result = {}
  for _, line in ipairs(lines) do
    local chunk = ""
    for _, character in ipairs(vim.fn.split(line, "\\zs")) do
      if chunk ~= "" and vim.fn.strdisplaywidth(chunk .. character) > width then
        result[#result + 1] = { { chunk, "Comment" } }
        chunk = ""
      end
      chunk = chunk .. character
    end
    result[#result + 1] = { { chunk, "Comment" } }
  end
  return result
end

local function paint(win, prepared)
  if not api.nvim_win_is_valid(win) or not api.nvim_buf_is_valid(prepared.buf) then
    return
  end
  api.nvim_buf_clear_namespace(prepared.buf, prepared.namespace, 0, -1)
  if api.nvim_buf_get_changedtick(prepared.buf) ~= prepared.tick or api.nvim_win_get_buf(win) ~= prepared.buf then
    return
  end
  local width = math.max(1, api.nvim_win_get_width(win) - vim.fn.getwininfo(win)[1].textoff)
  api.nvim__ns_set(prepared.namespace, { wins = { win } })
  for _, mark in ipairs(prepared.marks) do
    api.nvim_buf_set_extmark(prepared.buf, prepared.namespace, mark.row, 0, {
      virt_lines = wrap_lines(mark.lines, width),
      virt_lines_above = mark.above,
    })
  end
end

-- Persistent, window-scoped marks are required: ephemeral virt_lines do not
-- allocate screen rows. Remove stale anchors before a changed buffer is drawn.
api.nvim_set_decoration_provider(namespace, {
  on_win = function(_, win, buf)
    for _, state in pairs(states) do
      local prepared = state.windows[win]
      if prepared and (prepared.buf ~= buf or api.nvim_buf_get_changedtick(buf) ~= prepared.tick) then
        if api.nvim_buf_is_valid(prepared.buf) then
          api.nvim_buf_clear_namespace(prepared.buf, prepared.namespace, 0, -1)
        end
        state.windows[win] = nil
      end
    end
    return false
  end,
})

local function decorate(state)
  cancel_lookups(state)
  vim.cmd.redraw()
  if not state.enabled or not state.matches or not state.data or not state.view.cur_entry then
    return
  end
  local entry = state.view.cur_entry
  local generation = state.display_generation
  for _, side in ipairs({ "a", "b" }) do
    local window = state.view.cur_layout[side]
    local items = {}
    for _, item in ipairs(state.data.items) do
      if
        item.kind == "thread"
        and not item.isOutdated
        and item.side == (side == "a" and "LEFT" or "RIGHT")
        and (item.path == entry.path or (side == "a" and item.path == entry.oldpath))
      then
        items[#items + 1] = item
      end
    end
    if #items > 0 and window and window.id and api.nvim_win_is_valid(window.id) then
      local win = window.id
      local buf = api.nvim_win_get_buf(win)
      local revision = side == "a" and state.context.base or state.context.head
      local path = side == "a" and (entry.oldpath or entry.path) or entry.path
      local key = revision .. ":" .. path
      local function display(expected)
        if
          not valid(state)
          or generation ~= state.display_generation
          or not api.nvim_win_is_valid(win)
          or api.nvim_win_get_buf(win) ~= buf
        then
          return
        end
        state.blobs[side] = { key = key, lines = expected }
        if not vim.deep_equal(api.nvim_buf_get_lines(buf, 0, -1, false), expected) then
          return
        end
        local marks = {}
        for _, item in ipairs(items) do
          local file_comment = item.subjectType == "FILE"
          if file_comment or (type(item.line) == "number" and item.line >= 1 and item.line <= #expected) then
            marks[#marks + 1] = {
              row = file_comment and 0 or item.line - 1,
              above = file_comment,
              lines = body_lines(item),
              item = item,
            }
          end
        end
        local prepared = {
          buf = buf,
          tick = api.nvim_buf_get_changedtick(buf),
          marks = marks,
          namespace = state.namespaces[side],
        }
        state.windows[win] = prepared
        paint(win, prepared)
        vim.cmd.redraw()
      end
      local cached = state.blobs[side]
      if cached and cached.key == key then
        vim.schedule(function()
          display(cached.lines)
        end)
      else
        local process = run(
          { "git", "show", key },
          { cwd = state.context.repo, text = true, timeout = 10000 },
          vim.schedule_wrap(function(result)
            if result.code == 0 then
              display(vim.split((result.stdout or ""):gsub("\n$", ""), "\n", { plain = true }))
            end
          end)
        )
        state.lookups[#state.lookups + 1] = process
      end
    end
  end
end

local function refresh(state)
  state.generation = state.generation + 1
  local generation = state.generation
  if state.process then
    state.process:kill(15)
  end
  local function active()
    return valid(state) and state.generation == generation
  end
  state.process = run(
    { state.context.python, state.context.reader, state.context.url },
    { cwd = state.context.repo, text = true },
    vim.schedule_wrap(function(result)
      if not active() then
        return
      end
      state.process = nil
      local ok, data = pcall(vim.json.decode, result.stdout or "", { luanil = { object = true, array = true } })
      if result.code ~= 0 or not ok or type(data) ~= "table" or not data.pr or not data.items then
        notify(
          "Could not refresh GitHub comments: " .. vim.trim(result.stderr or "Invalid response"),
          vim.log.levels.WARN
        )
        return
      end
      local function finish(matches)
        state.process, state.data, state.matches = nil, data, matches
        decorate(state)
        if not matches then
          notify("GitHub PR revisions differ or are unavailable locally. Reopen the PR to see its inline comments.")
        end
      end
      if data.pr.url ~= state.context.url or data.pr.headRefOid ~= state.context.head then
        finish(false)
        return
      end
      state.process = run(
        { "git", "merge-base", data.pr.baseRefOid, data.pr.headRefOid },
        { cwd = state.context.repo, text = true, timeout = 10000 },
        vim.schedule_wrap(function(base)
          if active() then
            finish(base.code == 0 and vim.trim(base.stdout) == state.context.base)
          end
        end)
      )
    end)
  )
end

function M.attach(repo, url, revision)
  local lib = package.loaded["diffview.lib"]
  local view = lib and lib.get_current_view()
  if not view then
    return
  end
  if not api.nvim__ns_set then
    return notify("Update Neovim with ./install.sh nvim to display inline GitHub comments.", vim.log.levels.WARN)
  end
  M.close(view)
  local state = {
    view = view,
    context = M.context(repo, url, revision),
    generation = 0,
    display_generation = 0,
    lookups = {},
    blobs = {},
    windows = {},
    namespaces = {
      a = api.nvim_create_namespace("GitHubReview:" .. view.tabpage .. ":a"),
      b = api.nvim_create_namespace("GitHubReview:" .. view.tabpage .. ":b"),
    },
    enabled = true,
  }
  states[view] = state
  state.listener = function()
    vim.schedule(function()
      if valid(state) then
        decorate(state)
      end
    end)
  end
  view.emitter:on("file_open_post", state.listener)
  refresh(state)
end

function M.toggle()
  local state = current_state()
  if state then
    state.enabled = not state.enabled
    decorate(state)
  end
end

function M.refresh()
  local state = current_state()
  if state then
    refresh(state)
  end
end

function M.open_pr()
  local state = current_state()
  if state then
    local prepared = state.windows[api.nvim_get_current_win()]
    local row = api.nvim_win_get_cursor(0)[1] - 1
    local marks = prepared and api.nvim_buf_get_changedtick(prepared.buf) == prepared.tick and prepared.marks or {}
    for _, mark in ipairs(marks) do
      if mark.row == row then
        vim.ui.open(mark.item.url)
        return
      end
    end
    vim.ui.open(state.context.url)
  end
end

function M.close(view)
  local state = states[view]
  if not state then
    return
  end
  states[view] = nil
  cancel_lookups(state)
  if state.process then
    state.process:kill(15)
  end
  view.emitter:off(state.listener, "file_open_post")
  vim.cmd.redraw()
end

api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "BufWritePost" }, {
  group = api.nvim_create_augroup("GitHubReviewComments", { clear = true }),
  callback = function(event)
    for _, state in pairs(states) do
      local layout = state.view.cur_layout
      for _, side in ipairs({ "a", "b" }) do
        local window = layout and layout[side]
        if
          window
          and window.id
          and api.nvim_win_is_valid(window.id)
          and api.nvim_win_get_buf(window.id) == event.buf
        then
          decorate(state)
          break
        end
      end
    end
  end,
})

api.nvim_create_autocmd("WinResized", {
  group = "GitHubReviewComments",
  callback = function()
    for _, state in pairs(states) do
      for win, prepared in pairs(state.windows) do
        paint(win, prepared)
      end
    end
  end,
})

api.nvim_create_autocmd("VimLeavePre", {
  group = "GitHubReviewComments",
  callback = function()
    states = {}
    local pending = vim.tbl_keys(processes)
    for _, process in ipairs(pending) do
      process:kill(15)
    end
    -- Managed reviews run worktree cleanup after Neovim exits. Wait for the
    -- reader to terminate and reap its gh child before that cleanup begins.
    for _, process in ipairs(pending) do
      process:wait(1000)
    end
  end,
})

return M
