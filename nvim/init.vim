set runtimepath^=~/.vim runtimepath+=~/.vim/after
    let &packpath = &runtimepath
    source ~/.vimrc

""" vim plug """
call plug#begin('~/.vim/plugged')

Plug 'simrat39/rust-tools.nvim'
Plug 'autozimu/LanguageClient-neovim', { 'branch': 'next', 'do': 'bash install.sh' }

call plug#end()


""" mouse support """
if !has('nvim')
        set ttymouse=xterm2
    endif


