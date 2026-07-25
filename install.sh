#!/usr/bin/env bash
# Personal dotfiles installer.
#
# GitHub Codespaces runs this automatically on codespace create/rebuild when
# "Automatically install dotfiles" is enabled (github.com/settings/codespaces).
# It also works when run by hand on any Debian/Ubuntu box:  ./install.sh
#
# Sets up: Neovim (recent) + your config, the tools it expects (ripgrep, fd, a
# C compiler), lazygit, the Claude Code CLI, and git/editor defaults (git uses
# nvim, EDITOR=nvim). Safe to re-run (idempotent).
set -uo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
log() { printf '\033[1;34m[dotfiles]\033[0m %s\n' "$*"; }

# --- Neovim (config needs >= 0.11; distro packages are usually too old) ------
if ! command -v nvim >/dev/null 2>&1; then
  case "$(uname -m)" in
    x86_64)  asset="nvim-linux-x86_64" ;;
    aarch64) asset="nvim-linux-arm64" ;;
    *)       asset="" ;;
  esac
  if [ -n "$asset" ] &&
     curl -fL "https://github.com/neovim/neovim/releases/download/stable/${asset}.tar.gz" \
       -o /tmp/nvim.tar.gz; then
    log "Installing Neovim ($asset)"
    sudo rm -rf "/opt/${asset}"
    sudo tar -C /opt -xzf /tmp/nvim.tar.gz
    sudo ln -sf "/opt/${asset}/bin/nvim" /usr/local/bin/nvim
    rm -f /tmp/nvim.tar.gz
  else
    log "Prebuilt Neovim unavailable; falling back to apt (may be older)"
    sudo apt-get update -y && sudo apt-get install -y neovim
  fi
fi

# --- Tools the config expects: ripgrep, fd, a C compiler --------------------
pkgs=()
command -v rg >/dev/null 2>&1 || pkgs+=(ripgrep)
{ command -v fd >/dev/null 2>&1 || command -v fdfind >/dev/null 2>&1; } || pkgs+=(fd-find)
command -v cc >/dev/null 2>&1 || pkgs+=(build-essential)
if [ "${#pkgs[@]}" -gt 0 ]; then
  log "Installing: ${pkgs[*]}"
  sudo apt-get update -y && sudo apt-get install -y "${pkgs[@]}" || true
fi
# Debian ships fd as 'fdfind'; expose it under the 'fd' name the config uses.
if ! command -v fd >/dev/null 2>&1 && command -v fdfind >/dev/null 2>&1; then
  sudo ln -sf "$(command -v fdfind)" /usr/local/bin/fd
fi
command -v node >/dev/null 2>&1 ||
  log "note: Node.js not found — Copilot/LSP features need it (present in the default Codespaces image)"

# --- Symlink the Neovim config ----------------------------------------------
log "Linking ~/.config/nvim -> $DOTFILES/nvim"
mkdir -p "$HOME/.config"
if [ -e "$HOME/.config/nvim" ] && [ ! -L "$HOME/.config/nvim" ]; then
  mv "$HOME/.config/nvim" "$HOME/.config/nvim.bak.$(date +%s)"
fi
ln -sfn "$DOTFILES/nvim" "$HOME/.config/nvim"

# --- Git: use Neovim as the editor ------------------------------------------
git config --global core.editor nvim

# --- lazygit (LazyVim's <leader>gg) -----------------------------------------
if ! command -v lazygit >/dev/null 2>&1; then
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
    sudo install /tmp/lazygit /usr/local/bin/lazygit
    rm -f /tmp/lazygit.tar.gz /tmp/lazygit
  else
    log "lazygit install skipped (couldn't resolve latest release)"
  fi
fi

# --- EDITOR=nvim for interactive shells (managed block, non-destructive) ----
if [ -f "$HOME/.bashrc" ] && ! grep -qF "dotfiles managed" "$HOME/.bashrc"; then
  log "Adding EDITOR=nvim to ~/.bashrc"
  cat >> "$HOME/.bashrc" <<'RC'

# >>> dotfiles managed >>>
export EDITOR=nvim
export VISUAL=nvim
# <<< dotfiles managed <<<
RC
fi

# --- Claude Code CLI --------------------------------------------------------
if ! command -v claude >/dev/null 2>&1; then
  log "Installing Claude Code"
  curl -fsSL https://claude.ai/install.sh | bash ||
    log "Claude Code install failed (continuing) — see https://claude.com/claude-code"
fi

log "Done. Run 'nvim' — LazyVim installs plugins on first launch."
