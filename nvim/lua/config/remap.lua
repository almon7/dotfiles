vim.g.mapleader = " "
vim.keymap.set("n", "<leader>pv", vim.cmd.Ex)

-- Move selected line / block of text in visual mode by J or K
vim.keymap.set("v", "J", ":m '>+1<CR>gv=gv")
vim.keymap.set("v", "K", ":m '<-2<CR>gv=gv")
-- Bit by bit explanation:
-- :m '>+1: Move the selected lines to one line below the end of the selection.
-- <CR>: Press Enter to execute the command.
-- gv: Reselect the previously selected text.
-- =: Reindent the selected lines.

-- Keep cursor in place when joining lines
vim.keymap.set("n", "J", "mzJ`z") -- Bit by bit explanation:
-- mz: Mark the current position with the 'z' mark.
-- J: Join the current line with the next line.
-- `z: Move the cursor back to the position of the 'z' mark.

-- Scroll half a page and keep the cursor centered
vim.keymap.set("n", "<C-d>", "<C-d>zz")
vim.keymap.set("n", "<C-u>", "<C-u>zz")

-- Keep the search result centered when navigating through search results with n and N
vim.keymap.set("n", "n", "nzzzv")
vim.keymap.set("n", "N", "Nzzzv")

-- Paste over currently selected text without yanking it
vim.keymap.set("x", "<leader>p", "\"_dP")
-- Bit by bit explanation:
-- "_d: Delete the selected text into the black hole register (discard it).
-- P: Paste the previously yanked text before the cursor position.

-- Yank to system clipboard
vim.keymap.set("n", "<leader>y", "\"+y")
vim.keymap.set("v", "<leader>y", "\"+y")

-- Open a new tmux window with the tmux-sessionizer script
vim.keymap.set("n", "<C-f>", "<cmd>silent !tmux neww tmux-sessionizer<CR>")

-- Format the current buffer using the LSP formatting function when <leader>f is pressed in normal mode.
vim.keymap.set("n", "<leader>f", function()
    vim.lsp.buf.format()
end)

-- Search and replace the word under the cursor
vim.keymap.set("n", "<leader>s", [[:%s/\<<C-r><C-w>\>/<C-r><C-w>/gI<Left><Left><Left>]])

-- Make the current file executable
vim.keymap.set("n", "<leader>x", "<cmd>!chmod +x %<CR>", { silent = true })
