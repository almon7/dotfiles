# dotfiles

## nvim

To install vim, you will need to :

1. Install neovim
```
brew install neovim
```

2. Install Packer
```
git clone --depth 1 https://github.com/wbthomason/packer.nvim\
 ~/.local/share/nvim/site/pack/packer/start/packer.nvim
 ```

3. Install [nodejs](https://nodejs.org/en/download/) to use the LSP features and Copilot.

4. You may need to run `:PackerSync` in nvim to install the plugins.
