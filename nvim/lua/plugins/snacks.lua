local tmux_directions = {
  h = { flag = "L", edge = "left" },
  j = { flag = "D", edge = "bottom" },
  k = { flag = "U", edge = "top" },
  l = { flag = "R", edge = "right" },
}

local function select_tmux_pane(direction)
  local socket = vim.env.TMUX and vim.env.TMUX:match("^[^,]+")
  if not socket or not vim.env.TMUX_PANE then
    return
  end

  local target = vim.env.TMUX_PANE
  local tmux = tmux_directions[direction]
  vim.fn.system({
    "tmux",
    "-S",
    socket,
    "if-shell",
    "-F",
    "-t",
    target,
    "#{pane_at_" .. tmux.edge .. "}",
    "",
    "select-pane -t " .. target .. " -" .. tmux.flag,
  })
end

local function picker_window(picker, name)
  local id
  if name == "main" then
    id = picker.opts.source == "explorer" and picker.main or nil
    if not id or not vim.api.nvim_win_is_valid(id) then
      return
    end
  else
    local component = picker[name]
    local win = component and component.win
    if not win or not win:valid() or picker.layout:is_hidden(name) then
      return
    end
    id = win.win
  end

  local row, col = unpack(vim.api.nvim_win_get_position(id))
  local height = vim.api.nvim_win_get_height(id)
  local width = vim.api.nvim_win_get_width(id)
  return {
    name = name,
    id = id,
    top = row,
    bottom = row + height - 1,
    left = col,
    right = col + width - 1,
    row = row + (height - 1) / 2,
    col = col + (width - 1) / 2,
  }
end

-- Snacks pickers use floating windows, which vim-tmux-navigator does not
-- treat as directional splits. Move geometrically within the picker and hand
-- navigation to tmux when there is no picker window in that direction.
local function navigate_picker(picker, direction)
  -- The input and result list are one logical picker panel. Keep Ctrl-j/k
  -- available for tmux navigation; plain j/k and Ctrl-n/p still move results.
  if direction == "j" or direction == "k" then
    select_tmux_pane(direction)
    return
  end

  local windows = {}
  local current

  for _, name in ipairs({ "input", "list", "preview", "main" }) do
    local win = picker_window(picker, name)
    if win then
      windows[#windows + 1] = win
      if win.id == vim.api.nvim_get_current_win() then
        current = win
      end
    end
  end

  if not current then
    select_tmux_pane(direction)
    return
  end

  local horizontal = direction == "h" or direction == "l"
  local sign = (direction == "h" or direction == "k") and -1 or 1
  local best
  local best_score

  for _, candidate in ipairs(windows) do
    if candidate.id ~= current.id then
      local primary = horizontal and (candidate.col - current.col) or (candidate.row - current.row)
      local overlaps
      if horizontal then
        overlaps = math.max(current.top, candidate.top) <= math.min(current.bottom, candidate.bottom)
      else
        overlaps = math.max(current.left, candidate.left) <= math.min(current.right, candidate.right)
      end

      if primary * sign > 0 and overlaps then
        local perpendicular = horizontal and math.abs(candidate.row - current.row)
          or math.abs(candidate.col - current.col)
        local score = math.abs(primary) * 10000 + perpendicular
        if not best_score or score < best_score then
          best = candidate
          best_score = score
        end
      end
    end
  end

  if best then
    if best.name == "main" then
      vim.api.nvim_set_current_win(best.id)
    else
      picker:focus(best.name)
    end
  else
    select_tmux_pane(direction)
  end
end

local picker_navigation = {
  ["<c-h>"] = { "navigate_left", mode = { "n", "i" } },
  ["<c-j>"] = { "navigate_down", mode = { "n", "i" } },
  ["<c-k>"] = { "navigate_up", mode = { "n", "i" } },
  ["<c-l>"] = { "navigate_right", mode = { "n", "i" } },
}

return {
  "folke/snacks.nvim",
  opts = {
    picker = {
      actions = {
        navigate_left = function(picker)
          navigate_picker(picker, "h")
        end,
        navigate_down = function(picker)
          navigate_picker(picker, "j")
        end,
        navigate_up = function(picker)
          navigate_picker(picker, "k")
        end,
        navigate_right = function(picker)
          navigate_picker(picker, "l")
        end,
      },
      win = {
        input = { keys = picker_navigation },
        list = { keys = picker_navigation },
        preview = { keys = picker_navigation },
      },
      sources = {
        files = {
          hidden = true,
          ignored = false,
          args = {
            "--exclude",
            "node_modules",
            "--exclude",
            "build",
            "--exclude",
            "dist",
          },
        },
        grep = {
          hidden = false,
          ignored = false,
        },
        explorer = {
          hidden = true,
          ignored = true,
          win = {
            list = {
              wo = {
                number = true,
                relativenumber = true,
              },
            },
          },
        },
      },
    },
  },
}
