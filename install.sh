#!/usr/bin/env bash
# Personal dotfiles installer.
#
# Works on:
#   - macOS (via Homebrew)
#   - Debian / Ubuntu, including a bare VPS
#   - GitHub Codespaces, which runs this automatically on codespace *create*
#     when "Automatically install dotfiles" is enabled
#     (github.com/settings/codespaces)
#
# Sets up: Neovim (recent) + this config, tmux + this config, the tools the
# Neovim config expects (ripgrep, fd, a C compiler, Node), lazygit, the Claude
# Code CLI, and git/editor defaults (git uses nvim, EDITOR=nvim).
#
# Deliberately split in two halves:
#   1. packages — OS-specific, needs a package manager (and root on Linux)
#   2. configs  — portable, needs neither, so it always runs
# A box where you can't install anything still ends up with working configs.
#
# Safe to re-run (idempotent).
set -uo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
log() { printf '\033[1;34m[dotfiles]\033[0m %s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

# macOS ships bash 3.2, so: no associative arrays, and always guard an array
# expansion with a length check before expanding it under `set -u`.

# =============================================================================
# 1. Packages
# =============================================================================

install_macos() {
  if ! have brew; then
    log "Homebrew not found — skipping package installs."
    log "  Install it from https://brew.sh, then re-run this script."
    return
  fi

  pkgs=()
  have nvim    || pkgs+=(neovim)
  have rg      || pkgs+=(ripgrep)
  have fd      || pkgs+=(fd)
  have tmux    || pkgs+=(tmux)
  have lazygit || pkgs+=(lazygit)
  have node    || pkgs+=(node)   # Mason, Copilot, the JSON/Markdown LSPs
  if [ "${#pkgs[@]}" -gt 0 ]; then
    log "Installing: ${pkgs[*]}"
    brew install "${pkgs[@]}" || true
  fi

  # Treesitter compiles grammars from source and needs a C compiler.
  if ! xcode-select -p >/dev/null 2>&1; then
    log "Installing Command Line Tools (C compiler for Treesitter)"
    xcode-select --install || true
  fi

  # Icons in the statusline and pickers. Fonts are client-side: this only makes
  # sense on a machine with a display, hence macOS-only.
  if ! ls "$HOME/Library/Fonts" /Library/Fonts 2>/dev/null | grep -qi 'nerdfont\|nerd font'; then
    log "Installing JetBrainsMono Nerd Font — set it as your terminal font"
    brew install --cask font-jetbrains-mono-nerd-font || true
  fi
}

install_linux() {
  # Root needs no sudo, and minimal VPS images often don't ship it at all.
  SUDO=""
  if [ "$(id -u)" -ne 0 ]; then
    if ! have sudo; then
      log "note: not root and no sudo — skipping package installs"
      return
    fi
    # Ask for elevation once, up front, rather than stalling on a hidden prompt
    # halfway through. Non-interactive (Codespaces) with a password-gated sudo:
    # skip rather than hang — the config half below still runs.
    if ! sudo -n true 2>/dev/null; then
      if [ ! -t 0 ]; then
        log "note: sudo needs a password and there is no terminal — skipping package installs"
        return
      fi
      log "Elevated permissions needed for package installs."
      if ! sudo -v; then
        log "note: sudo declined — skipping package installs"
        return
      fi
    fi
    SUDO=sudo
  fi

  if ! have apt-get; then
    log "note: no apt-get — install Neovim >= 0.11, tmux, ripgrep, fd, Node and a"
    log "      C compiler by hand (nvim/README.md has Arch and Fedora commands)"
    return
  fi

  # --- Bootstrap: everything below fetches over HTTPS, and minimal cloud
  # images don't always ship curl. Must come before the first curl call. ------
  if ! have curl; then
    log "Installing curl"
    $SUDO apt-get update -y && $SUDO apt-get install -y curl ca-certificates || true
  fi

  # --- Neovim (config needs >= 0.11; distro packages are usually too old) ----
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
      $SUDO apt-get update -y && $SUDO apt-get install -y neovim
    fi
  fi

  # --- Tools the config expects: ripgrep, fd, a C compiler, tmux ------------
  pkgs=()
  have rg || pkgs+=(ripgrep)
  { have fd || have fdfind; } || pkgs+=(fd-find)
  have cc || pkgs+=(build-essential)
  have tmux || pkgs+=(tmux)
  if [ "${#pkgs[@]}" -gt 0 ]; then
    log "Installing: ${pkgs[*]}"
    $SUDO apt-get update -y && $SUDO apt-get install -y "${pkgs[@]}" || true
  fi
  # Debian ships fd as 'fdfind'; expose it under the 'fd' name the config uses.
  if ! have fd && have fdfind; then
    $SUDO ln -sf "$(command -v fdfind)" /usr/local/bin/fd
  fi

  # --- Node: Mason, Copilot and the JSON/Markdown LSPs need it. Codespaces
  # images ship it; a bare VPS does not. -------------------------------------
  if ! have node; then
    log "Installing Node.js 22"
    if curl -fsSL https://deb.nodesource.com/setup_22.x | $SUDO -E bash -; then
      $SUDO apt-get install -y nodejs || true
    else
      log "NodeSource unavailable; falling back to apt (older Node)"
      $SUDO apt-get install -y nodejs npm || true
    fi
  fi

  # --- lazygit (LazyVim's <leader>gg) ---------------------------------------
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
      log "lazygit install skipped (couldn't resolve latest release)"
    fi
  fi
}

case "$(uname -s)" in
  Darwin) install_macos ;;
  Linux)  install_linux ;;
  *)      log "note: unrecognised OS '$(uname -s)' — skipping package installs" ;;
esac

# =============================================================================
# 2. Configs — portable: no package manager, no root
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

log "Setting git's editor to nvim"
git config --global core.editor nvim

# EDITOR=nvim for interactive shells (managed block, non-destructive).
# Both rc files: bash on a Linux box, zsh on macOS.
for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
  [ -f "$rc" ] || continue
  grep -qF "dotfiles managed" "$rc" && continue
  log "Adding EDITOR=nvim to $rc"
  cat >> "$rc" <<'RC'

# >>> dotfiles managed >>>
export EDITOR=nvim
export VISUAL=nvim
# <<< dotfiles managed <<<
RC
done

# =============================================================================
# 3. Claude Code — per-user install, needs no root on either OS
# =============================================================================

if ! have claude; then
  log "Installing Claude Code"
  curl -fsSL https://claude.ai/install.sh | bash ||
    log "Claude Code install failed (continuing) — see https://claude.com/claude-code"
fi

log "Done. Run 'nvim' — LazyVim installs plugins on first launch."
