-- lua/config/git-warn.lua
-- Persistent red statusline badges + notification for uncommitted / unpushed work.

local M = {}

-- State is per-repo-dir to handle multiple repos in the same session.
-- Key: git root dir, Value: { uncommitted, unpushed, no_remote }
local repo_state = {}
local checking = false
local last_notified_dir = nil

local function get_git_root(dir)
    local r = vim.fn.systemlist("git -C " .. vim.fn.shellescape(dir) .. " rev-parse --show-toplevel 2>/dev/null")
    if vim.v.shell_error ~= 0 or not r or #r == 0 then return nil end
    return r[1]
end

local function cwd_for_buf()
    local path = vim.api.nvim_buf_get_name(0)
    if path == "" then path = vim.fn.getcwd() end
    return vim.fn.fnamemodify(path, ":h")
end

local function current_git_root()
    return get_git_root(cwd_for_buf())
end

local function async_check()
    if checking then return end

    -- Skip non-normal buffers (quickfix, terminal, help, etc.)
    local bt = vim.bo.buftype
    if bt ~= "" then return end

    local dir = cwd_for_buf()
    checking = true

    -- Resolve the actual git root so state is keyed consistently across
    -- any subdirectory of the same repo.
    vim.system({ "git", "-C", dir, "rev-parse", "--show-toplevel" }, { text = true }, function(r0)
        if r0.code ~= 0 then
            -- Not a git repo
            checking = false
            vim.schedule(function() vim.cmd("redrawstatus!") end)
            return
        end

        local root = r0.stdout:gsub("%s+$", "")
        if not repo_state[root] then
            repo_state[root] = { uncommitted = false, unpushed = 0, no_remote = false }
        end
        local st = repo_state[root]

        -- 1. Uncommitted changes
        vim.system({ "git", "-C", root, "status", "--porcelain" }, { text = true }, function(r1)
            st.uncommitted = r1.code == 0 and r1.stdout ~= nil and #r1.stdout > 0

            -- 2. Unpushed commits
            vim.system({ "git", "-C", root, "log", "@{u}..HEAD", "--oneline" }, { text = true }, function(r2)
                checking = false

                if r2.code ~= 0 then
                    -- Likely no upstream configured
                    st.no_remote = true
                    st.unpushed  = 0
                else
                    st.no_remote = false
                    local count = 0
                    if r2.stdout then
                        for _ in r2.stdout:gmatch("[^\n]+") do count = count + 1 end
                    end
                    st.unpushed = count
                end

                vim.schedule(function()
                    vim.cmd("redrawstatus!")

                    -- Notify once per (focus cycle × repo root)
                    local notify_key = root
                    if last_notified_dir ~= notify_key and (st.uncommitted or st.unpushed > 0 or st.no_remote) then
                        last_notified_dir = notify_key
                        local msgs = {}
                        if st.uncommitted          then table.insert(msgs, "uncommitted changes") end
                        if st.unpushed > 0         then table.insert(msgs, st.unpushed .. " unpushed commit(s)") end
                        if st.no_remote            then table.insert(msgs, "no upstream remote configured") end
                        vim.notify("Git Warning: " .. table.concat(msgs, " + "), vim.log.levels.WARN)
                    end
                end)
            end)
        end)
    end)
end

-- Called from statusline via %{%...%}
function M.statusline()
    local root = current_git_root()
    if not root then return "" end

    local st = repo_state[root]
    if not st then return "" end  -- check not yet complete, show nothing until ready

    local commit_badge = st.uncommitted
        and "%#GitWarnUncommitted# ● UNCOMMITTED %*"
        or  "%#GitWarnClean# ✓ COMMITTED %*"

    local push_badge
    if st.no_remote then
        push_badge = "%#GitWarnUnpushed# ? NO REMOTE %*"
    elseif st.unpushed > 0 then
        push_badge = ("%#GitWarnUnpushed# ▲ " .. st.unpushed .. " UNPUSHED %*")
    else
        push_badge = "%#GitWarnClean# ✓ PUSHED %*"
    end

    return commit_badge .. " " .. push_badge
end

function M.setup()
    local function set_hls()
        vim.api.nvim_set_hl(0, "GitWarnUncommitted", { fg = "#ffffff", bg = "#c0392b", bold = true })
        vim.api.nvim_set_hl(0, "GitWarnUnpushed",    { fg = "#ffffff", bg = "#d35400", bold = true })
        vim.api.nvim_set_hl(0, "GitWarnClean",       { fg = "#ffffff", bg = "#27ae60", bold = true })
    end
    set_hls()

    local group = vim.api.nvim_create_augroup("GitWarn", { clear = true })

    vim.api.nvim_create_autocmd("ColorScheme", {
        group    = group,
        callback = set_hls,
    })

    -- Re-check and allow fresh notification each time focus returns.
    -- This is the key behaviour for multi-laptop use: switching back to nvim
    -- after committing/pushing in another terminal will immediately update.
    vim.api.nvim_create_autocmd("FocusGained", {
        group    = group,
        callback = function()
            last_notified_dir = nil       -- allow a fresh notification on re-focus
            vim.defer_fn(async_check, 300)
        end,
    })

    -- BufWritePost: re-check after every save (most important trigger)
    -- BufEnter: re-check on buffer switch, but guard against non-normal buffers
    --           (the guard is also inside async_check, but early return is cheaper)
    vim.api.nvim_create_autocmd("BufWritePost", {
        group    = group,
        callback = function() vim.defer_fn(async_check, 300) end,
    })

    vim.api.nvim_create_autocmd("BufEnter", {
        group    = group,
        callback = function()
            if vim.bo.buftype ~= "" then return end
            vim.defer_fn(async_check, 300)
        end,
    })

    -- Periodic refresh every 60 s to catch commits/pushes made in another terminal.
    local timer = vim.uv.new_timer()
    timer:start(2000, 60000, vim.schedule_wrap(async_check))

    -- Statusline: left = file info, right = git badges + position
    vim.o.statusline = " %f %m%r%=%{%v:lua.require('config.git-warn').statusline()%}  %l:%c  %p%% "
end

return M