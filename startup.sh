# /bin/bash

# install ohmyzsh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

# install brew
-c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
(echo; echo 'eval "$(/opt/homebrew/bin/brew shellenv)"') >> /Users/miriah.peterson/dotfiles/zsh/zsh_profile
    eval "$(/opt/homebrew/bin/brew shellenv)"

brew upgrade

brew install neovim
#install vim plug
sh -c 'curl -fLo "${XDG_DATA_HOME:-$HOME/.local/share}"/nvim/site/autoload/plug.vim --create-dirs \
       https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim'

brew install podman

# start podman
podman machine init
podman machine start

brew install jq

touch ~/.secrets

# check if ssh key exists
 echo -e "Checking if you have setup a key for serve ssh connection ..."
ls -al ~/.ssh | grep id_ed25519.pub 
if [ $? -eq 0 ]
then
git clone git@github.com:Soypete/dotfiles.git
ln -s dotfiles/bash/bashrc .bashrc
ln -s dotfiles/zsh/zshrc .zshrc
ln -s dotfiles/nvim/init.vim .config/nvim/init.vim

source ~.zshrc
else
  echo -e "Set up a ssh key please "
fi

