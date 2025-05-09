# /bin/bash

# install ohmyzsh
# sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

#curl -sS https://webi.sh/webi | sh; \
#source ~/.config/envman/PATH.env

#webi brew@stable jq@stable gh@stable terraform@stable go@stable python@stable  rg@stable

#curl -LsSf https://astral.sh/uv/install.sh | sh
#uv tool install ruff@latest

# brew install neovim

# brew install podman

# start podman
#podman machine init
#podman machine start

touch ~/.secrets

# brew install 1password-cli

echo "export SSH_AUTH_SOCK=~/Library/Group\ Containers/2BUA8C4S2C.com.1password/t/agent.sock" >>./zsh/zsh_profile
rm ~/.bashrc
ln -s dotfiles/bash/bashrc ~/.bashrc
rm ~/.zshrc
ln -s dotfiles/zsh/zshrc ~/.zshrc
rm ~/.zshprofile
ln -s dotfiles/zsh/zsh_profile ~/.zsh_profile

source ~/.zshrc

mkdir ~/code/
