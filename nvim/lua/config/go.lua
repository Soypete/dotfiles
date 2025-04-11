vim.g.go_def_mode = 'gopls'
vim.g.go_info_mode = 'gopls'
vim.g.go_term_enabled = 1
vim.g.go_list_type = 'quickfix'

vim.g.go_fmt_command = 'goimports'
vim.g.go_fmt_autosave = 1
vim.g.go_imports_autosave = 1
vim.g.go_mod_fmt_autosave = 1

vim.g.go_highlight_build_constraints = 1
vim.g.go_highlight_extra_types = 1
vim.g.go_highlight_fields = 1
vim.g.go_highlight_functions = 1
vim.g.go_highlight_methods = 1
vim.g.go_highlight_operators = 1
vim.g.go_highlight_structs = 1
vim.g.go_highlight_types = 1

vim.g.go_metalinter_autosave = 1
vim.g.go_metalinter_enabled = {
  'godot', 'godox', 'gofmt', 'govet', 'revive', 'errcheck', 'deadcode',
  'gosimple', 'ifeffassign', 'staticcheck', 'structcheck', 'typecheck',
  'unused', 'varcheck', 'bodyclose', 'dogsled', 'goconst', 'gocyclo',
  'importas', 'rowserrcheck', 'sqlclosecheck', 'misspell'
}

vim.g.gotests_bin = os.getenv("GOPATH") .. "/bin/gotests"
