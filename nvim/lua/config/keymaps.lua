local map = vim.api.nvim_set_keymap
local opts = { noremap = true, silent = true }

-- Telescope
map("n", "<leader>ff", "<cmd>Telescope find_files<CR>", opts)
map("n", "<leader>fg", "<cmd>Telescope live_grep<CR>", opts)
map("n", "<leader>fb", "<cmd>Telescope buffers<CR>", opts)
map("n", "<leader>fh", "<cmd>Telescope help_tags<CR>", opts)

-- NerdTree
map("n", "<leader>n", ":NERDTreeFocus<CR>", opts)
map("n", "<C-n>", ":NERDTree<CR>", opts)
map("n", "<C-t>", ":NERDTreeToggle<CR>", opts)
map("n", "<C-f>", ":NERDTreeFind<CR>", opts)
vim.g.NERDTreeShowHidden = 1

