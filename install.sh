#!/usr/bin/env bash
# Personal Neovim, tmux, and WezTerm dotfiles installer.
#
# Works on:
#   - macOS (via Homebrew)
#   - Debian / Ubuntu, including a bare VPS
#   - GitHub Codespaces
#
# Sets up Neovim, tmux, and WezTerm dotfile links, and the tools the Neovim
# configuration expects: ripgrep, fd, a C compiler, make, Git, Node,
# python3-venv, lazygit, and a Nerd Font on macOS.
#
# Deliberately split in two halves:
#   1. packages - OS-specific, needs a package manager (and root on Linux)
#   2. configs  - portable, needs neither, so it always runs
#
# Safe to re-run (idempotent).
set -uo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() { printf '\033[1;34m[dotfiles]\033[0m %s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

# macOS ships Bash 3.2, so avoid associative arrays and guard array expansions
# with a length check under `set -u`.

# =============================================================================
# 1. Packages
# =============================================================================

install_macos() {
  if ! have brew; then
    log "Homebrew not found - skipping package installs."
    log "  Install it from https://brew.sh, then re-run this script."
    return
  fi

  pkgs=()
  have nvim    || pkgs+=(neovim)
  have tmux    || pkgs+=(tmux)
  have rg      || pkgs+=(ripgrep)
  have fd      || pkgs+=(fd)
  have git     || pkgs+=(git)
  have node    || pkgs+=(node)       # Mason, Copilot, JSON/Markdown LSPs
  have python3 || pkgs+=(python)     # Mason packages installed from PyPI
  have lazygit || pkgs+=(lazygit)    # LazyVim's <leader>gg integration

  if [ "${#pkgs[@]}" -gt 0 ]; then
    log "Installing: ${pkgs[*]}"
    brew install "${pkgs[@]}" || true
  fi

  # Treesitter compiles grammars from source and needs a C compiler.
  if ! xcode-select -p >/dev/null 2>&1; then
    log "Installing Command Line Tools (C compiler for Treesitter)"
    xcode-select --install || true
  fi

  # Icons used by Neovim and tmux status lines.
  if ! ls "$HOME/Library/Fonts" /Library/Fonts 2>/dev/null |
       grep -qi 'nerdfont\|nerd font'; then
    log "Installing JetBrainsMono Nerd Font - set it as your terminal font"
    brew install --cask font-jetbrains-mono-nerd-font || true
  fi
}

install_linux() {
  # Root needs no sudo, and minimal VPS images often do not ship it.
  SUDO=""
  if [ "$(id -u)" -ne 0 ]; then
    if ! have sudo; then
      log "note: not root and no sudo - skipping package installs"
      return
    fi

    # Ask for elevation once. In a non-interactive shell, skip instead of
    # hanging on a password prompt; the config half below still runs.
    if ! sudo -n true 2>/dev/null; then
      if [ ! -t 0 ]; then
        log "note: sudo needs a password and there is no terminal - skipping package installs"
        return
      fi
      log "Elevated permissions needed for package installs."
      if ! sudo -v; then
        log "note: sudo declined - skipping package installs"
        return
      fi
    fi
    SUDO=sudo
  fi

  if ! have apt-get; then
    log "note: no apt-get - install Neovim >= 0.11, tmux, ripgrep, fd, Git,"
    log "      Node, Python venv support, make, and a C compiler by hand"
    return
  fi

  # Minimal cloud images do not always include curl or CA certificates.
  if ! have curl; then
    log "Installing curl"
    $SUDO apt-get update -y &&
      $SUDO apt-get install -y curl ca-certificates || true
  fi

  # The Neovim config needs >= 0.11; distro packages are often older.
  if ! have nvim; then
    case "$(uname -m)" in
      x86_64)  asset="nvim-linux-x86_64" ;;
      aarch64) asset="nvim-linux-arm64" ;;
      *)       asset="" ;;
    esac

    if [ -n "$asset" ] &&
       curl -fL "https://github.com/neovim/neovim/releases/download/stable/${asset}.tar.gz" \
         -o /tmp/nvim.tar.gz; then
      log "Installing Neovim ($asset)"
      $SUDO rm -rf "/opt/${asset}"
      $SUDO tar -C /opt -xzf /tmp/nvim.tar.gz
      $SUDO ln -sf "/opt/${asset}/bin/nvim" /usr/local/bin/nvim
      rm -f /tmp/nvim.tar.gz
    else
      log "Prebuilt Neovim unavailable; falling back to apt (may be older)"
      $SUDO apt-get update -y && $SUDO apt-get install -y neovim || true
    fi
  fi

  # Neovim/tmux and tools used directly by the Neovim configuration.
  pkgs=()
  have tmux || pkgs+=(tmux)
  have rg || pkgs+=(ripgrep)
  { have fd || have fdfind; } || pkgs+=(fd-find)
  have cc || pkgs+=(build-essential)
  have make || pkgs+=(make)
  have git || pkgs+=(git)

  # Mason installs some language tools from PyPI via `python3 -m venv`.
  if ! have python3; then
    pkgs+=(python3 python3-venv)
  elif ! python3 -m venv --help >/dev/null 2>&1; then
    pkgs+=(python3-venv)
  fi

  if [ "${#pkgs[@]}" -gt 0 ]; then
    log "Installing: ${pkgs[*]}"
    $SUDO apt-get update -y &&
      $SUDO apt-get install -y "${pkgs[@]}" || true
  fi

  # Debian installs fd as `fdfind`; expose the name the config expects.
  if ! have fd && have fdfind; then
    $SUDO ln -sf "$(command -v fdfind)" /usr/local/bin/fd
  fi

  # Mason, Copilot, and the JSON/Markdown LSPs need Node.
  if ! have node; then
    log "Installing Node.js 22"
    if [ -n "$SUDO" ]; then
      if curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -; then
        sudo apt-get install -y nodejs || true
      else
        log "NodeSource unavailable; falling back to apt (older Node)"
        sudo apt-get install -y nodejs npm || true
      fi
    else
      if curl -fsSL https://deb.nodesource.com/setup_22.x | bash -; then
        apt-get install -y nodejs || true
      else
        log "NodeSource unavailable; falling back to apt (older Node)"
        apt-get install -y nodejs npm || true
      fi
    fi
  fi

  # Used by LazyVim's <leader>gg integration.
  if ! have lazygit; then
    case "$(uname -m)" in
      x86_64)  lg_arch="x86_64" ;;
      aarch64) lg_arch="arm64" ;;
      *)       lg_arch="" ;;
    esac

    lg_ver="$(curl -fsSL https://api.github.com/repos/jesseduffield/lazygit/releases/latest |
      sed -n 's/.*"tag_name": *"v\([^"]*\)".*/\1/p' | head -1)"

    if [ -n "$lg_arch" ] && [ -n "$lg_ver" ] &&
       curl -fL "https://github.com/jesseduffield/lazygit/releases/latest/download/lazygit_${lg_ver}_Linux_${lg_arch}.tar.gz" \
         -o /tmp/lazygit.tar.gz; then
      log "Installing lazygit $lg_ver"
      tar -C /tmp -xzf /tmp/lazygit.tar.gz lazygit
      $SUDO install /tmp/lazygit /usr/local/bin/lazygit
      rm -f /tmp/lazygit.tar.gz /tmp/lazygit
    else
      log "lazygit install skipped (could not resolve latest release)"
    fi
  fi
}

case "$(uname -s)" in
  Darwin) install_macos ;;
  Linux)  install_linux ;;
  *)      log "note: unrecognised OS '$(uname -s)' - skipping package installs" ;;
esac

# =============================================================================
# 2. Configs - portable: no package manager, no root
# =============================================================================

# link <target> <linkname>, moving a real file or directory out of the way first
link() {
  if [ -e "$2" ] && [ ! -L "$2" ]; then
    log "Backing up existing $2"
    mv "$2" "$2.bak.$(date +%s)"
  fi
  ln -sfn "$1" "$2"
}

log "Linking ~/.config/nvim -> $DOTFILES/nvim"
mkdir -p "$HOME/.config"
link "$DOTFILES/nvim" "$HOME/.config/nvim"

log "Linking ~/.tmux.conf -> $DOTFILES/tmux/tmux.conf"
link "$DOTFILES/tmux/tmux.conf" "$HOME/.tmux.conf"

log "Linking ~/.wezterm.lua -> $DOTFILES/wezterm/.wezterm.lua"
link "$DOTFILES/wezterm/.wezterm.lua" "$HOME/.wezterm.lua"

if have git; then
  log "Setting Git's editor to nvim"
  git config --global core.editor nvim
fi

# EDITOR and VISUAL for interactive Bash and Zsh shells. Version 3 replaces
# the older managed block, which also added an unrelated PATH entry.
RC_BLOCK_VERSION=3
for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
  [ -f "$rc" ] || continue
  grep -qF ">>> dotfiles managed v${RC_BLOCK_VERSION} >>>" "$rc" && continue

  if grep -qE '^# >>> dotfiles managed v[0-9]+ >>>$' "$rc"; then
    log "Replacing outdated managed block in $rc"
    # This spelling of `sed -i` works with both BSD sed and GNU sed.
    sed -i".bak.$(date +%s)" \
      '/^# >>> dotfiles managed v[0-9][0-9]* >>>$/,/^# <<< dotfiles managed v[0-9][0-9]* <<<$/{d;}' \
      "$rc"
  fi

  log "Adding managed block to $rc"
  cat >> "$rc" <<RC

# >>> dotfiles managed v${RC_BLOCK_VERSION} >>>
export EDITOR=nvim
export VISUAL=nvim
# <<< dotfiles managed v${RC_BLOCK_VERSION} <<<
RC
done

log "Done. Run 'nvim' and 'tmux' to finish first-launch setup."
