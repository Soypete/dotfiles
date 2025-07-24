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
ARCH=$(uname -m)
if [ "$ARCH" = "arm64" ]; then
  curl -LO https://github.com/neovim/neovim/releases/download/nightly/nvim-macos-arm64.tar.gz
  tar xzf nvim-macos-arm64.tar.gz
  ./nvim-macos-arm64/bin/nvim

  #non-webi tools
  brew install podman
  brew install fzf
  brew install 1password-cli
else
  curl -LO https://github.com/neovim/neovim/releases/download/nightly/nvim-linux-x86_64.tar.gz
  tar xzf nvim-linux-x86_64.tar.gz
  ./nvim-linux-x86_64/bin/nvim

  sudo apt update
  sudo apt install podman
  sudo apt install fzf

  curl -sS https://downloads.1password.com/linux/keys/1password.asc |
    sudo gpg --dearmor --output /usr/share/keyrings/1password-archive-keyring.gpg &&
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/$(dpkg --print-architecture) stable main" |
    sudo tee /etc/apt/sources.list.d/1password.list &&
    sudo mkdir -p /etc/debsig/policies/AC2D62742012EA22/ &&
    curl -sS https://downloads.1password.com/linux/debian/debsig/1password.pol |
    sudo tee /etc/debsig/policies/AC2D62742012EA22/1password.pol &&
    sudo mkdir -p /usr/share/debsig/keyrings/AC2D62742012EA22 &&
    curl -sS https://downloads.1password.com/linux/keys/1password.asc |
    sudo gpg --dearmor --output /usr/share/debsig/keyrings/AC2D62742012EA22/debsig.gpg &&
    sudo apt update && sudo apt install 1password-cli
fi

#start podman
podman machine init
podman machine start

touch ~/.secrets

rm ~/.bashrc
ln -s dotfiles/bash/bashrc ~/.bashrc
rm ~/.zshrc
ln -s dotfiles/zsh/zshrc ~/.zshrc
rm ~/.zsh_profile
ln -s dotfiles/zsh/zsh_profile ~/.zsh_profile

source ~/.zshrc

# I like to put all my code stuff here
mkdir ~/code/
