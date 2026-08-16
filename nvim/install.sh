#!/usr/bin/env bash
# Install Neovim and link its configuration.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LABEL=nvim
source "$DIR/../install-lib.sh"
parse_args "$@"

install_neovim_linux() {
  case "$(uname -m)" in
    x86_64) archive=nvim-linux-x86_64 ;;
    aarch64) archive=nvim-linux-arm64 ;;
    *) log 'No Neovim build is available for this CPU.'; return 1 ;;
  esac

  local file
  file="$(mktemp)"
  curl -fL "https://github.com/neovim/neovim/releases/download/stable/$archive.tar.gz" -o "$file"
  as_root rm -rf "/opt/$archive"
  as_root tar -C /opt -xzf "$file"
  as_root ln -sfn "/opt/$archive/bin/nvim" /usr/local/bin/nvim
  rm "$file"
}

if ! $CONFIG_ONLY; then
  case "$(uname -s)" in
    Darwin)
      brew install neovim ripgrep fd node python
      brew install --cask font-jetbrains-mono-nerd-font
      xcode-select -p >/dev/null 2>&1 || xcode-select --install
      ;;
    Linux)
      apt_install curl ca-certificates ripgrep fd-find nodejs npm python3 python3-venv build-essential
      has nvim || install_neovim_linux
      if ! has fd && has fdfind; then
        as_root ln -sf "$(command -v fdfind)" /usr/local/bin/fd
      fi
      ;;
    *) log 'Only macOS and Linux are supported.'; exit 1 ;;
  esac
fi

link_config "$DIR" "$HOME/.config/nvim"
log 'Run nvim to finish plugin setup.'
