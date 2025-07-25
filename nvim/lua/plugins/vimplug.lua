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

	{ "nvim-lua/plenary.nvim" },
	-- Telescope
	{
		"nvim-telescope/telescope.nvim",
		cmd = "Telescope",
		version = false, -- telescope did only one release, so use HEAD for now
		dependencies = {
			{
				"nvim-telescope/telescope-fzf-native.nvim",
				build = (build_cmd ~= "cmake") and "make"
					or "cmake -S. -Bbuild -DCMAKE_BUILD_TYPE=Release && cmake --build build --config Release && cmake --install build --prefix build",
				enabled = build_cmd ~= nil,
				config = function(plugin)
					LazyVim.on_load("telescope.nvim", function()
						local ok, err = pcall(require("telescope").load_extension, "fzf")
						if not ok then
							local lib = plugin.dir .. "/build/libfzf." .. (LazyVim.is_win() and "dll" or "so")
							if not vim.uv.fs_stat(lib) then
								LazyVim.warn("`telescope-fzf-native.nvim` not built. Rebuilding...")
								require("lazy").build({ plugins = { plugin }, show = false }):wait(function()
									LazyVim.info("Rebuilding `telescope-fzf-native.nvim` done.\nPlease restart Neovim.")
								end)
							else
								LazyVim.error("Failed to load `telescope-fzf-native.nvim`:\n" .. err)
							end
						end
					end)
				end,
			},
		},
		keys = {
			{
				"<leader>,",
				"<cmd>Telescope buffers sort_mru=true sort_lastused=true<cr>",
				desc = "Switch Buffer",
			},
			{ "<leader>/", LazyVim.pick("live_grep"), desc = "Grep (Root Dir)" },
			{ "<leader>:", "<cmd>Telescope command_history<cr>", desc = "Command History" },
			{ "<leader><space>", LazyVim.pick("files"), desc = "Find Files (Root Dir)" },
			-- find
			{
				"<leader>fb",
				"<cmd>Telescope buffers sort_mru=true sort_lastused=true ignore_current_buffer=true<cr>",
				desc = "Buffers",
			},
			{ "<leader>fc", LazyVim.pick.config_files(), desc = "Find Config File" },
			{ "<leader>ff", LazyVim.pick("files"), desc = "Find Files (Root Dir)" },
			{ "<leader>fF", LazyVim.pick("files", { root = false }), desc = "Find Files (cwd)" },
			{ "<leader>fg", "<cmd>Telescope git_files<cr>", desc = "Find Files (git-files)" },
			{ "<leader>fr", "<cmd>Telescope oldfiles<cr>", desc = "Recent" },
			{ "<leader>fR", LazyVim.pick("oldfiles", { cwd = vim.uv.cwd() }), desc = "Recent (cwd)" },
			-- git
			{ "<leader>gc", "<cmd>Telescope git_commits<CR>", desc = "Commits" },
			{ "<leader>gs", "<cmd>Telescope git_status<CR>", desc = "Status" },
			-- search
			{ '<leader>s"', "<cmd>Telescope registers<cr>", desc = "Registers" },
			{ "<leader>sa", "<cmd>Telescope autocommands<cr>", desc = "Auto Commands" },
			{ "<leader>sb", "<cmd>Telescope current_buffer_fuzzy_find<cr>", desc = "Buffer" },
			{ "<leader>sc", "<cmd>Telescope command_history<cr>", desc = "Command History" },
			{ "<leader>sC", "<cmd>Telescope commands<cr>", desc = "Commands" },
			{ "<leader>sd", "<cmd>Telescope diagnostics bufnr=0<cr>", desc = "Document Diagnostics" },
			{ "<leader>sD", "<cmd>Telescope diagnostics<cr>", desc = "Workspace Diagnostics" },
			{ "<leader>sg", LazyVim.pick("live_grep"), desc = "Grep (Root Dir)" },
			{ "<leader>sG", LazyVim.pick("live_grep", { root = false }), desc = "Grep (cwd)" },
			{ "<leader>sh", "<cmd>Telescope help_tags<cr>", desc = "Help Pages" },
			{ "<leader>sH", "<cmd>Telescope highlights<cr>", desc = "Search Highlight Groups" },
			{ "<leader>sj", "<cmd>Telescope jumplist<cr>", desc = "Jumplist" },
			{ "<leader>sk", "<cmd>Telescope keymaps<cr>", desc = "Key Maps" },
			{ "<leader>sl", "<cmd>Telescope loclist<cr>", desc = "Location List" },
			{ "<leader>sM", "<cmd>Telescope man_pages<cr>", desc = "Man Pages" },
			{ "<leader>sm", "<cmd>Telescope marks<cr>", desc = "Jump to Mark" },
			{ "<leader>so", "<cmd>Telescope vim_options<cr>", desc = "Options" },
			{ "<leader>sR", "<cmd>Telescope resume<cr>", desc = "Resume" },
			{ "<leader>sq", "<cmd>Telescope quickfix<cr>", desc = "Quickfix List" },
			{ "<leader>sw", LazyVim.pick("grep_string", { word_match = "-w" }), desc = "Word (Root Dir)" },
			{ "<leader>sW", LazyVim.pick("grep_string", { root = false, word_match = "-w" }), desc = "Word (cwd)" },
			{ "<leader>sw", LazyVim.pick("grep_string"), mode = "v", desc = "Selection (Root Dir)" },
			{ "<leader>sW", LazyVim.pick("grep_string", { root = false }), mode = "v", desc = "Selection (cwd)" },
			{ "<leader>uC", LazyVim.pick("colorscheme", { enable_preview = true }), desc = "Colorscheme with Preview" },
			{
				"<leader>ss",
				function()
					require("telescope.builtin").lsp_document_symbols({
						symbols = LazyVim.config.get_kind_filter(),
					})
				end,
				desc = "Goto Symbol",
			},
			{
				"<leader>sS",
				function()
					require("telescope.builtin").lsp_dynamic_workspace_symbols({
						symbols = LazyVim.config.get_kind_filter(),
					})
				end,
				desc = "Goto Symbol (Workspace)",
			},
		},
		opts = function()
			local actions = require("telescope.actions")

			local open_with_trouble = function(...)
				return require("trouble.sources.telescope").open(...)
			end
			local find_files_no_ignore = function()
				local action_state = require("telescope.actions.state")
				local line = action_state.get_current_line()
				LazyVim.pick("find_files", { no_ignore = true, default_text = line })()
			end
			local find_files_with_hidden = function()
				local action_state = require("telescope.actions.state")
				local line = action_state.get_current_line()
				LazyVim.pick("find_files", { hidden = true, default_text = line })()
			end

			local function find_command()
				if 1 == vim.fn.executable("rg") then
					return { "rg", "--files", "--color", "never", "-g", "!.git" }
				elseif 1 == vim.fn.executable("fd") then
					return { "fd", "--type", "f", "--color", "never", "-E", ".git" }
				elseif 1 == vim.fn.executable("fdfind") then
					return { "fdfind", "--type", "f", "--color", "never", "-E", ".git" }
				elseif 1 == vim.fn.executable("find") and vim.fn.has("win32") == 0 then
					return { "find", ".", "-type", "f" }
				elseif 1 == vim.fn.executable("where") then
					return { "where", "/r", ".", "*" }
				end
			end

			return {
				defaults = {
					prompt_prefix = " ",
					selection_caret = " ",
					-- open files in the first window that is an actual file.
					-- use the current window if no other window is available.
					get_selection_window = function()
						local wins = vim.api.nvim_list_wins()
						table.insert(wins, 1, vim.api.nvim_get_current_win())
						for _, win in ipairs(wins) do
							local buf = vim.api.nvim_win_get_buf(win)
							if vim.bo[buf].buftype == "" then
								return win
							end
						end
						return 0
					end,
					mappings = {
						i = {
							["<c-t>"] = open_with_trouble,
							["<a-t>"] = open_with_trouble,
							["<a-i>"] = find_files_no_ignore,
							["<a-h>"] = find_files_with_hidden,
							["<C-Down>"] = actions.cycle_history_next,
							["<C-Up>"] = actions.cycle_history_prev,
							["<C-f>"] = actions.preview_scrolling_down,
							["<C-b>"] = actions.preview_scrolling_up,
						},
						n = {
							["q"] = actions.close,
						},
					},
				},
				pickers = {
					find_files = {
						find_command = find_command,
						hidden = true,
					},
				},
			}
		end,
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

	-- llamavim
	{
		"ggml-org/llama.vim",
	},

	----Copilot
	--{
	--	"zbirenbaum/copilot.lua",
	--	cmd = "Copilot",
	--	build = ":Copilot auth",
	--	event = "BufReadPost",
	--	opts = {
	--		suggestion = {
	--			enabled = not vim.g.ai_cmp,
	--			auto_trigger = true,
	--			hide_during_completion = vim.g.ai_cmp,
	--			keymap = {
	--				accept = false, -- handled by nvim-cmp / blink.cmp
	--				next = "<M-]>",
	--				prev = "<M-[>",
	--			},
	--		},
	--		panel = { enabled = false },
	--		filetypes = {
	--			markdown = true,
	--			help = true,
	--		},
	--	},
	--},
	--{
	--	"CopilotC-Nvim/CopilotChat.nvim",
	--	branch = "main",
	--	cmd = "CopilotChat",
	--	opts = function()
	--		local user = vim.env.USER or "User"
	--		user = user:sub(1, 1):upper() .. user:sub(2)
	--		return {
	--			auto_insert_mode = true,
	--			question_header = "  " .. user .. " ",
	--			answer_header = "  Copilot ",
	--			window = {
	--				width = 0.4,
	--			},
	--		}
	--	end,
	--	keys = {
	--		{ "<c-s>", "<CR>", ft = "copilot-chat", desc = "Submit Prompt", remap = true },
	--		{ "<leader>a", "", desc = "+ai", mode = { "n", "v" } },
	--		{
	--			"<leader>aa",
	--			function()
	--				return require("CopilotChat").toggle()
	--			end,
	--			desc = "Toggle (CopilotChat)",
	--			mode = { "n", "v" },
	--		},
	--		{
	--			"<leader>ax",
	--			function()
	--				return require("CopilotChat").reset()
	--			end,
	--			desc = "Clear (CopilotChat)",
	--			mode = { "n", "v" },
	--		},
	--		{
	--			"<leader>aq",
	--			function()
	--				vim.ui.input({
	--					prompt = "Quick Chat: ",
	--				}, function(input)
	--					if input ~= "" then
	--						require("CopilotChat").ask(input)
	--					end
	--				end)
	--			end,
	--			desc = "Quick Chat (CopilotChat)",
	--			mode = { "n", "v" },
	--		},
	--		{
	--			"<leader>ap",
	--			function()
	--				require("CopilotChat").select_prompt()
	--			end,
	--			desc = "Prompt Actions (CopilotChat)",
	--			mode = { "n", "v" },
	--		},
	--	},
	--	config = function(_, opts)
	--		local chat = require("CopilotChat")

	--		vim.api.nvim_create_autocmd("BufEnter", {
	--			pattern = "copilot-chat",
	--			callback = function()
	--				vim.opt_local.relativenumber = false
	--				vim.opt_local.number = false
	--			end,
	--		})

	--		chat.setup(opts)
	--	end,
	--},

	-- Others
	"wakatime/vim-wakatime",
}
