return {
    "viniciusteixeiradias/kanban.nvim",
    cmd = { "Kanban", "KanbanClose", "KanbanToggle" },
    keys = {
      {
        "<leader>tk",
        function()
          require("kanban").open()
        end,
        desc = "Open Kanban board",
      },
      {
        "<leader>tt",
        function()
          require("kanban").toggle()
        end,
        desc = "Toggle Kanban board",
      },
    },
    opts = {},
  }
