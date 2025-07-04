# /bin/bash
cd $HOME

install ohmyzsh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

curl -sS https://webi.sh/webi | sh
source ~/.config/envman/PATH.env

webi brew@stable jq@stable gh@stable terraform@stable go@stable python@stable rg@stable node@stable

curl -LsSf https://astral.sh/uv/install.sh | sh
uv tool install ruff@latest

# install neovim
curl -LO https://github.com/neovim/neovim/releases/download/nightly/nvim-macos-x86_64.tar.gz
tar xzf nvim-macos-x86_64.tar.gz

./nvim-macos-x86_64/bin/nvim

#non-webi tools
brew install podman
brew install fzf

#start podman
podman machine init
podman machine start

touch ~/.secrets

brew install 1password-cli

rm ~/.bashrc
ln -s dotfiles/bash/bashrc ~/.bashrc
rm ~/.zshrc
ln -s dotfiles/zsh/zshrc ~/.zshrc
rm ~/.zsh_profile
ln -s dotfiles/zsh/zsh_profile ~/.zsh_profile

source ~/.zshrc

# I like to put all my code stuff here
mkdir ~/code/
