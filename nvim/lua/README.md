# SETUP

```bash
brew install neovim
```

open neovim
```bash
nvim
```

create `init.vim`

```
:exe 'edit '.stdpath('config').'/init.vim'
:write ++p
```

point it to vimrc by adding this to file

```
set runtimepath^=~/.vim runtimepath+=~/.vim/after
let &packpath = &runtimepath
source ~/.vimrc
```

Reference:
- [nvim docs](https://neovim.io/doc/user/nvim.html#nvim-from-vim)
