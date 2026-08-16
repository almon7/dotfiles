#!/usr/bin/env bash
# Install Neovim and its supporting tools, then link this folder's config.
set -uo pipefail

DESCRIPTION="Neovim config and its command-line dependencies"
[ "${1:-}" = "--description" ] && { printf '%s\n' "$DESCRIPTION"; exit 0; }

CONFIG_ONLY=false
case "${1:-}" in
  --config-only) CONFIG_ONLY=true ;;
  '') ;;
  -h|--help) printf 'Usage: %s [--config-only]\n' "$0"; exit 0 ;;
  *) printf 'Unknown option: %s\n' "$1" >&2; exit 2 ;;
esac

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_FAILED=false
log() { printf '\033[1;34m[nvim]\033[0m %s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }
package_failed() {
  PACKAGE_FAILED=true
  log "Package error: $*"
}

install_macos() {
  pkgs=()
  have nvim || pkgs+=(neovim)
  have rg || pkgs+=(ripgrep)
  have fd || pkgs+=(fd)
  have node || pkgs+=(node)
  have python3 || pkgs+=(python)
  have lazygit || pkgs+=(lazygit)

  font_installed=false
  if ls "$HOME/Library/Fonts" /Library/Fonts 2>/dev/null | grep -qi 'nerdfont\|nerd font'; then
    font_installed=true
  fi

  if have brew; then
    if [ "${#pkgs[@]}" -gt 0 ]; then
      log "Installing: ${pkgs[*]}"
      brew install "${pkgs[@]}" || package_failed "Homebrew could not install: ${pkgs[*]}"
    fi
    if ! $font_installed; then
      log "Installing JetBrainsMono Nerd Font"
      brew install --cask font-jetbrains-mono-nerd-font || package_failed "Could not install JetBrainsMono Nerd Font."
    fi
  elif [ "${#pkgs[@]}" -gt 0 ] || ! $font_installed; then
    package_failed "Homebrew not found. Install it from https://brew.sh and re-run."
  fi

  if ! xcode-select -p >/dev/null 2>&1; then
    log "Installing Command Line Tools (C compiler for Treesitter)"
    xcode-select --install || package_failed "Could not start the Command Line Tools installer."
  fi
}

install_linux() {
  sudo_cmd=""
  if [ "$(id -u)" -ne 0 ]; then
    if ! have sudo; then package_failed "Not root and no sudo; package installs were skipped."; return; fi
    if ! sudo -n true 2>/dev/null; then
      if [ ! -t 0 ]; then package_failed "sudo needs a terminal; package installs were skipped."; return; fi
      log "Elevated permissions needed for package installs."
      if ! sudo -v; then package_failed "sudo authorization failed; package installs were skipped."; return; fi
    fi
    sudo_cmd=sudo
  fi
  if ! have apt-get; then
    package_failed "No apt-get found. Install Neovim >= 0.11, ripgrep, fd, Node, Python venv, make, a C compiler, and lazygit manually."
    return
  fi
  if ! have curl; then
    log "Installing curl"
    if ! { $sudo_cmd apt-get update -y && $sudo_cmd apt-get install -y curl ca-certificates; }; then
      package_failed "Could not install curl and CA certificates."
      return
    fi
  fi
  if ! have nvim; then
    case "$(uname -m)" in
      x86_64) asset="nvim-linux-x86_64" ;;
      aarch64) asset="nvim-linux-arm64" ;;
      *) asset="" ;;
    esac
    if [ -n "$asset" ] && curl -fL "https://github.com/neovim/neovim/releases/download/stable/${asset}.tar.gz" -o /tmp/nvim.tar.gz; then
      log "Installing Neovim ($asset)"
      if ! { $sudo_cmd rm -rf "/opt/${asset}" &&
             $sudo_cmd tar -C /opt -xzf /tmp/nvim.tar.gz &&
             $sudo_cmd ln -sf "/opt/${asset}/bin/nvim" /usr/local/bin/nvim; }; then
        package_failed "Could not install the Neovim archive."
      fi
      rm -f /tmp/nvim.tar.gz
    else
      log "Prebuilt Neovim unavailable; falling back to apt (may be older)"
      if ! { $sudo_cmd apt-get update -y && $sudo_cmd apt-get install -y neovim; }; then
        package_failed "Could not install Neovim."
      fi
    fi
  fi
  pkgs=()
  have rg || pkgs+=(ripgrep)
  { have fd || have fdfind; } || pkgs+=(fd-find)
  have cc || pkgs+=(build-essential)
  have make || pkgs+=(make)
  if ! have python3; then
    pkgs+=(python3 python3-venv)
  elif ! python3 -m venv --help >/dev/null 2>&1; then
    pkgs+=(python3-venv)
  fi
  if [ "${#pkgs[@]}" -gt 0 ]; then
    log "Installing: ${pkgs[*]}"
    if ! { $sudo_cmd apt-get update -y && $sudo_cmd apt-get install -y "${pkgs[@]}"; }; then
      package_failed "apt could not install: ${pkgs[*]}"
    fi
  fi
  if ! have fd && have fdfind; then
    $sudo_cmd ln -sf "$(command -v fdfind)" /usr/local/bin/fd || package_failed "Could not create the fd command link."
  fi
  if ! have node; then
    log "Installing Node.js 22"
    if [ -n "$sudo_cmd" ]; then
      if curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -; then
        sudo apt-get install -y nodejs || package_failed "Could not install Node.js."
      else
        log "NodeSource unavailable; falling back to apt (older Node)"
        sudo apt-get install -y nodejs npm || package_failed "Could not install Node.js from apt."
      fi
    else
      if curl -fsSL https://deb.nodesource.com/setup_22.x | bash -; then
        apt-get install -y nodejs || package_failed "Could not install Node.js."
      else
        log "NodeSource unavailable; falling back to apt (older Node)"
        apt-get install -y nodejs npm || package_failed "Could not install Node.js from apt."
      fi
    fi
  fi
  if ! have lazygit; then
    case "$(uname -m)" in
      x86_64) lg_arch="x86_64" ;;
      aarch64) lg_arch="arm64" ;;
      *) lg_arch="" ;;
    esac
    lg_ver="$(curl -fsSL https://api.github.com/repos/jesseduffield/lazygit/releases/latest | sed -n 's/.*"tag_name": *"v\([^"]*\)".*/\1/p' | head -1)"
    if [ -n "$lg_arch" ] && [ -n "$lg_ver" ] && curl -fL "https://github.com/jesseduffield/lazygit/releases/latest/download/lazygit_${lg_ver}_Linux_${lg_arch}.tar.gz" -o /tmp/lazygit.tar.gz; then
      log "Installing lazygit $lg_ver"
      if ! { tar -C /tmp -xzf /tmp/lazygit.tar.gz lazygit &&
             $sudo_cmd install /tmp/lazygit /usr/local/bin/lazygit; }; then
        package_failed "Could not install lazygit."
      fi
      rm -f /tmp/lazygit.tar.gz /tmp/lazygit
    else
      package_failed "Could not resolve or download the latest lazygit release."
    fi
  fi
}

if ! $CONFIG_ONLY; then
  case "$(uname -s)" in
    Darwin) install_macos ;;
    Linux) install_linux ;;
    *) package_failed "Unsupported OS; package installs were skipped." ;;
  esac
fi

mkdir -p "$HOME/.config" || exit 1
if [ -e "$HOME/.config/nvim" ] && [ ! -L "$HOME/.config/nvim" ]; then
  backup="$HOME/.config/nvim.bak.$(date +%s)"
  log "Backing up existing ~/.config/nvim to $backup"
  mv "$HOME/.config/nvim" "$backup" || exit 1
fi
log "Linking ~/.config/nvim -> $DIR"
ln -sfn "$DIR" "$HOME/.config/nvim" || exit 1

if $PACKAGE_FAILED; then
  log "Config installed, but one or more packages failed."
  exit 1
fi
log "Done. Run nvim to finish first-launch setup."
