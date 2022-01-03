set runtimepath^=~/.vim runtimepath+=~/.vim/after
    let &packpath = &runtimepath
    source ~/.vimrc

""" vim plug """
call plug#begin('~/.vim/plugged')

Plug 'buoto/gotests-vim'
Plug 'ekalinin/dockerfile.vim'
Plug 'fatih/vim-go'
Plug 'jremmen/vim-ripgrep'
Plug 'junegunn/seoul256.vim'
Plug 'junegunn/vim-easy-align'
Plug 'luochen1990/rainbow'
Plug 'nsf/gocode', { 'rtp': 'vim', 'do': '~/.vim/plugged/gocode/vim/symlink.sh' }
Plug 'scrooloose/nerdtree'
Plug 'scrooloose/syntastic'
Plug 'tpope/vim-fugitive'
Plug 'tpope/vim-commentary'
Plug 'rust-lang/rust.vim'
Plug 'valloric/youcompleteme'
Plug 'wakatime/vim-wakatime'


Plug 'simrat39/rust-tools.nvim'
Plug 'autozimu/LanguageClient-neovim', { 'branch': 'next', 'do': 'bash install.sh' }

call plug#end()


""" mouse support """
if !has('nvim')
        set ttymouse=xterm2
    endif

"" python support
let g:python3_host_prog = '/opt/homebrew/bin/python3'

