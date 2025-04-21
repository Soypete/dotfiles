return {

	-- Go
	{
		"ray-x/go.nvim",
		dependencies = { -- optional packages
			"ray-x/guihua.lua",
			"neovim/nvim-lspconfig",
			"nvim-treesitter/nvim-treesitter",
		},
		config = function()
			require("go").setup()
		end,
		event = { "CmdlineEnter" },
		ft = { "go", "gomod" },
		build = ':lua require("go.install").update_all_sync()', -- if you need to install/update all binaries
	},
	{
		"fredrikaverpil/neotest-golang",
	},

	-- LSP
	{
		"nvim-treesitter/nvim-treesitter",
		opts = { ensure_installed = { "go", "gomod", "gowork", "gosum", "terraform", "hcl" } },
	},
	"williamboman/mason-lspconfig.nvim",
	{
		"williamboman/mason.nvim",
		opts = {
			ensure_installed = { "gomodifytags", "impl", "goimports", "markdownlint-cli2", "markdown-toc", "tflint" },
		},
	},
	{
		"neovim/nvim-lspconfig",
		opts = {
			servers = {
				-- bacon_ls = { enabled = diagnostics == "bacon-ls" },
				rust_analyzer = { enabled = false },
				marksman = {},
				terraformls = {},
				gopls = {
					settings = {
						gopls = {
							gofumpt = true,
							codelenses = {
								gc_details = false,
								generate = true,
								regenerate_cgo = true,
								run_govulncheck = true,
								test = true,
								tidy = true,
								upgrade_dependency = true,
								vendor = true,
							},
							hints = {
								assignVariableTypes = true,
								compositeLiteralFields = true,
								compositeLiteralTypes = true,
								constantValues = true,
								functionTypeParameters = true,
								parameterNames = true,
								rangeVariableTypes = true,
							},
							analyses = {
								nilness = true,
								unusedparams = true,
								unusedwrite = true,
								useany = true,
							},
							usePlaceholders = true,
							completeUnimported = true,
							staticcheck = true,
							directoryFilters = { "-.git", "-.vscode", "-.idea", "-.vscode-test", "-node_modules" },
							semanticTokens = true,
						},
					},
				},
				ruff = {
					cmd_env = { RUFF_TRACE = "messages" },
					init_options = {
						settings = {
							logLevel = "error",
						},
					},
					keys = {
						{
							"<leader>co",
							LazyVim.lsp.action["source.organizeImports"],
							desc = "Organize Imports",
						},
					},
				},
				ruff_lsp = {
					keys = {
						{
							"<leader>co",
							LazyVim.lsp.action["source.organizeImports"],
							desc = "Organize Imports",
						},
					},
				},
			},
			setup = {
				gopls = function(_, opts)
					-- workaround for gopls not supporting semanticTokensProvider
					-- https://github.com/golang/go/issues/54531#issuecomment-1464982242
					LazyVim.lsp.on_attach(function(client, _)
						if not client.server_capabilities.semanticTokensProvider then
							local semantic = client.config.capabilities.textDocument.semanticTokens
							client.server_capabilities.semanticTokensProvider = {
								full = true,
								legend = {
									tokenTypes = semantic.tokenTypes,
									tokenModifiers = semantic.tokenModifiers,
								},
								range = true,
							}
						end
					end, "gopls")
					-- end workaround
				end,
				[ruff] = function()
					LazyVim.lsp.on_attach(function(client, _) end, ruff)
				end,
			},
		},
	},

	-- Telescope
	{ "nvim-lua/plenary.nvim" },
	{
		"nvim-telescope/telescope.nvim",
		optional = true,
		specs = {
			{
				"ANGkeith/telescope-terraform-doc.nvim",
				ft = { "terraform", "hcl" },
				config = function()
					LazyVim.on_load("telescope.nvim", function()
						require("telescope").load_extension("terraform_doc")
					end)
				end,
			},
			{
				"cappyzawa/telescope-terraform.nvim",
				ft = { "terraform", "hcl" },
				config = function()
					LazyVim.on_load("telescope.nvim", function()
						require("telescope").load_extension("terraform")
					end)
				end,
			},
		},
	},

	-- Tree/File Explorer
	"preservim/nerdtree",

	-- CSV and filetypes
	"ekalinin/dockerfile.vim",
	"mechatroner/rainbow_csv",
	"ziglang/zig.vim",
	"rust-lang/rust.vim",

	-- Tools
	"jremmen/vim-ripgrep",
	"tpope/vim-fugitive",
	"tpope/vim-commentary",
	"luochen1990/rainbow",
	{ "folke/todo-comments.nvim", opts = {} },

	-- nightfly
	{ "bluz71/vim-nightfly-colors", name = "nightfly", lazy = false, priority = 1000 },

	-- Others
	"wakatime/vim-wakatime",
}
