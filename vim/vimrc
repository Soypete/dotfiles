set nocompatible  
set spelllang=en
set spell
syntax enable
filetype plugin indent on
set tabstop=4
set shiftwidth=4
set number

colorscheme desert

""" vim plug"""
call plug#begin('~/.vim/plugged')

Plug 'junegunn/seoul256.vim'
Plug 'junegunn/vim-easy-align'
Plug 'scrooloose/nerdtree'
Plug 'fatih/vim-go'
Plug 'kien/rainbow_parentheses.vim'
Plug 'valloric/youcompleteme'
Plug 'rust-lang/rust.vim'
Plug 'jremmen/vim-ripgrep'
Plug 'wakatime/vim-wakatime'

call plug#end()

  """"" Go Bindings """""
"au Filetype go nmap <leader>l :GoLint<CR>
"au Filetype go nmap <leader>b :GoToggleBreakpoint<CR>
"au Filetype go map <leader>d :GoDebug<CR>
let g:go_highlight_functions = 1
let g:go_highlight_methods = 1
let g:go_highlight_fields = 1
let g:go_highlight_types = 1
let g:go_highlight_operators = 1
let g:go_fmt_command = "goimports"
let g:go_fmt_autosave = 1

let g:go_term_enabled = 1
let g:go_list_type = "quickfix"

let g:syntastic_always_populate_loc_list = 1
let g:syntastic_auto_loc_list = 1
let g:syntastic_check_on_open = 1
let g:syntastic_check_on_w = 1
let g:syntastic_check_autosave = 1
let g:syntastic_go_checkers = ["gofmt", "govet", "golint", "errcheck", "deadcode", "gometalinter"]
let g:syntastic_style_error_symbol=">>"
let g:syntastic_style_warning_symbol=">>"
let g:go_highlight_build_constraints = 1
let g:go_highlight_extra_types = 1
let g:go_highlight_fields = 1
let g:go_highlight_functions = 1
let g:go_highlight_methods = 1
let g:go_highlight_operators = 1
let g:go_highlight_structs = 1
let g:go_highlight_types = 1
highlight SyntasticError ctermbg=231
highlight SyntasticWarningLine ctermbg=130

"python-mode
let g:pymode_python = 'python3'

" NerdTree
autocmd vimenter * NERDTree
map <C-n> :NERDTreeToggle<CR>

" RUST
let g:rustfmt_autosave = 1

" Rainbow Paranetheses
let g:rainbow_active = 1 "set to 0 if you want to enable it later via :RainbowToggle
