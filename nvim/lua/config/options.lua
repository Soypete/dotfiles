vim.opt.compatible = false
vim.opt.spelllang = { "en" }
vim.cmd("syntax enable")
vim.cmd("filetype plugin indent on")

vim.opt.tabstop = 2
vim.opt.shiftwidth = 2
vim.opt.number = true
vim.opt.termguicolors = true
vim.opt.scrolloff = 20
vim.opt.clipboard = "unnamed"

vim.cmd([[
  autocmd BufNewFile,BufRead *.csv set filetype=csv_semicolon
  autocmd BufNewFile,BufRead *.dat set filetype=csv_pipe
]])

-- NerdTree autocmd to close if it's the only window
vim.api.nvim_create_augroup("nerdtree_close", { clear = true })
vim.api.nvim_create_autocmd("BufEnter", {
	group = "nerdtree_close",
	command = [[if tabpagenr('$') == 1 && winnr('$') == 1 && exists('b:NERDTree') && b:NERDTree.isTabTree() | quit | endif]],
})

vim.g.lazyvim_python_ruff = "ruff"

-- Colorscheme and Lightline
-- vim.cmd("colorscheme nightfly")
-- vim.g.lightline = { colorscheme = "nightfly" }
-- vim.g.nightflyCursorColor = 1
--
-- Run gofmt + goimports on save
local format_sync_grp = vim.api.nvim_create_augroup("goimports", {})
vim.api.nvim_create_autocmd("BufWritePre", {
	pattern = "*.go",
	callback = function()
		require("go.format").goimports()
	end,
	group = format_sync_grp,
})
