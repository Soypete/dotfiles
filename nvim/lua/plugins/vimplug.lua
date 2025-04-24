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
							-- gofumpt = true,
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

	--Copilot
	{
		"zbirenbaum/copilot.lua",
		cmd = "Copilot",
		build = ":Copilot auth",
		event = "BufReadPost",
		opts = {
			suggestion = {
				enabled = not vim.g.ai_cmp,
				auto_trigger = true,
				hide_during_completion = vim.g.ai_cmp,
				keymap = {
					accept = false, -- handled by nvim-cmp / blink.cmp
					next = "<M-]>",
					prev = "<M-[>",
				},
			},
			panel = { enabled = false },
			filetypes = {
				markdown = true,
				help = true,
			},
		},
	},
	{
		"CopilotC-Nvim/CopilotChat.nvim",
		branch = "main",
		cmd = "CopilotChat",
		opts = function()
			local user = vim.env.USER or "User"
			user = user:sub(1, 1):upper() .. user:sub(2)
			return {
				auto_insert_mode = true,
				question_header = "  " .. user .. " ",
				answer_header = "  Copilot ",
				window = {
					width = 0.4,
				},
			}
		end,
		keys = {
			{ "<c-s>", "<CR>", ft = "copilot-chat", desc = "Submit Prompt", remap = true },
			{ "<leader>a", "", desc = "+ai", mode = { "n", "v" } },
			{
				"<leader>aa",
				function()
					return require("CopilotChat").toggle()
				end,
				desc = "Toggle (CopilotChat)",
				mode = { "n", "v" },
			},
			{
				"<leader>ax",
				function()
					return require("CopilotChat").reset()
				end,
				desc = "Clear (CopilotChat)",
				mode = { "n", "v" },
			},
			{
				"<leader>aq",
				function()
					vim.ui.input({
						prompt = "Quick Chat: ",
					}, function(input)
						if input ~= "" then
							require("CopilotChat").ask(input)
						end
					end)
				end,
				desc = "Quick Chat (CopilotChat)",
				mode = { "n", "v" },
			},
			{
				"<leader>ap",
				function()
					require("CopilotChat").select_prompt()
				end,
				desc = "Prompt Actions (CopilotChat)",
				mode = { "n", "v" },
			},
		},
		config = function(_, opts)
			local chat = require("CopilotChat")

			vim.api.nvim_create_autocmd("BufEnter", {
				pattern = "copilot-chat",
				callback = function()
					vim.opt_local.relativenumber = false
					vim.opt_local.number = false
				end,
			})

			chat.setup(opts)
		end,
	},

	-- Others
	"wakatime/vim-wakatime",
}
