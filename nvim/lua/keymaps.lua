local map = vim.api.nvim_set_keymap
local opts = { noremap = true, silent = true }

-- Leader key
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- General keymaps
map("n", "<C-s>", ":w<CR>", opts)                      -- Save file
map("n", "<C-w>", ":bd<CR>", opts)                     -- Close buffer
map("n", "<C-q>", ":qa!<CR>", opts)                    -- Quit
map("n", "<C-e>", ":lua Snacks.dashboard()<CR>", opts) -- Dashboard
map("n", "<C-n>", ":ene | startinsert<CR>", opts)      -- New buffer
map("n", "<C-b>", ":NvimTreeToggle<CR>", opts)         -- NvimTree

-- Window navigation
map("n", "<C-h>", "<C-w>h", opts)
map("n", "<C-l>", "<C-w>l", opts)
map("n", "<C-j>", "<C-w>j", opts)
map("n", "<C-k>", "<C-w>k", opts)

-- Terminal
map("n", "<C-t>", ":lua Snacks.terminal.open()<CR>", opts)
map("n", "<leader>tt", ":lua Snacks.terminal.toggle()<CR>", opts)

-- ============================================================
-- Telescope mappings
-- ============================================================
map("n", "<leader>ff", ":Telescope find_files<CR>", opts)       -- Find files
map("n", "<leader>fg", ":Telescope live_grep<CR>", opts)       -- Grep text
map("n", "<leader>fb", ":Telescope buffers<CR>", opts)         -- List buffers
map("n", "<leader>fh", ":Telescope help_tags<CR>", opts)       -- Help tags
map("n", "<leader>fr", ":Telescope oldfiles<CR>", opts)        -- Recent files
map("n", "<leader>fk", ":Telescope keymaps<CR>", opts)         -- Keymap help

-- ============================================================
-- Quickfix / loclist navigation
-- ============================================================
map("n", "]q", ":cnext<CR>", opts)
map("n", "[q", ":cprev<CR>", opts)

-- ============================================================
-- Buffer navigation
-- ============================================================
map("n", "<Tab>", ":bnext<CR>", opts)
map("n", "<S-Tab>", ":bprev<CR>", opts)

-- ============================================================
-- Better indenting
-- ============================================================
map("v", "<", "<gv", opts)
map("v", ">", ">gv", opts)

-- ============================================================
-- Move lines up/down (visual mode)
-- ============================================================
map("v", "<A-j>", ":m .+1<CR>==", opts)
map("v", "<A-k>", ":m .-2<CR>==", opts)

-- ============================================================
-- Split management
-- ============================================================
map("n", "<leader>sv", ":vsplit<CR>", opts)
map("n", "<leader>sh", ":split<CR>", opts)
map("n", "<leader>sc", ":close<CR>", opts)

-- ============================================================
-- Toggle options
-- ============================================================
map("n", "<leader>tn", ":set nonumber!<CR>", opts)
map("n", "<leader>tr", ":set norelativenumber!<CR>", opts)
map("n", "<leader>tw", ":set wrap!<CR>", opts)
