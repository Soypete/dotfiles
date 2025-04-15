local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
	vim.fn.system({
		"git",
		"clone",
		"--filter=blob:none",
		"https://github.com/folke/lazy.nvim.git",
		"--branch=stable", -- latest stable release
		lazypath,
	})
end
vim.opt.rtp:prepend(lazypath)

-- setup lazy.nvim
require("lazy").setup({
	spec = {
		{ "LazyVim/LazyVim", import = "lazyvim.plugins" },
		-- import your plugins
		{ import = "plugins" },
	},
	-- configure any other settings here. see the documentation for more details.
	-- colorscheme that will be used when installing plugins.
	-- install = { colorscheme = { "bluz71/vim-nightfly-colors", name = "nightfly", lazy = false, priority = 1000 }},
	-- automatically check for plugin updates
	checker = { enabled = true },
})
