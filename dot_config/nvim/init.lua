-- ~/.config/nvim/init.lua

-- Use the system clipboard for all yanks/deletes/puts
vim.opt.clipboard = "unnamedplus"

local map = vim.keymap.set
local opts = { noremap = true, silent = true }

-- Normal + Visual mode mappings
-- H -> beginning of line
-- L -> end of line
-- J -> half-page down
-- K -> half-page up

-- Beginning/end of line
map({ 'n', 'v' }, 'H', '^', opts)  -- beginning (non-blank)
map({ 'n', 'v' }, 'L', '$', opts)  -- end of line

-- Half-page jumps
map({ 'n', 'v' }, 'J', '<C-d>', opts)
map({ 'n', 'v' }, 'K', '<C-u>', opts)

-- Optional: keep cursor centered when moving half-pages
-- map({ 'n', 'v' }, 'J', '<C-d>zz', opts)
-- map({ 'n', 'v' }, 'K', '<C-u>zz', opts)

