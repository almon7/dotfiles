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
# Neovim config expects (ripgrep, fd, a C compiler, Node, python3-venv for
# Mason), lazygit, Docker + Compose v2, uv, the Claude Code CLI, and git/editor
# defaults (git uses nvim, EDITOR=nvim).
#
# Deliberately split in two halves:
#   1. packages — OS-specific, needs a package manager (and root on Linux)
#   2. configs  — portable, needs neither, so it always runs
# A box where you can't install anything still ends up with working configs.
#
# Safe to re-run (idempotent).
set -uo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# uv and the Claude Code CLI install here. Put it on PATH for the rest of this
# run so the `have` checks below see what we just installed; the rc block in
# part 2 makes it stick for future shells.
export PATH="$HOME/.local/bin:$PATH"

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
  have uv      || pkgs+=(uv)     # Python projects: host-side venv for the LSP
  if [ "${#pkgs[@]}" -gt 0 ]; then
    log "Installing: ${pkgs[*]}"
    brew install "${pkgs[@]}" || true
  fi

  # Docker on macOS means Docker Desktop (or OrbStack/Colima) — a GUI app with
  # a VM behind it, not something to install unattended from a dotfiles script.
  if ! have docker || ! docker compose version >/dev/null 2>&1; then
    log "note: no 'docker compose' — install Docker Desktop from"
    log "      https://docker.com/products/docker-desktop (or 'brew install --cask orbstack')"
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
  # build-essential pulls make in, but only gets installed when there's no cc —
  # an image that already ships gcc would otherwise leave `make` missing.
  have make || pkgs+=(make)
  have git || pkgs+=(git)
  have gpg || pkgs+=(gnupg)   # dearmouring Docker's apt signing key, below
  # Mason installs basedpyright, ruff and debugpy from PyPI, and its PyPI
  # installer shells out to `python3 -m venv`. Cloud images ship python3 for
  # cloud-init but leave the venv module out, so the Python LSP silently
  # fails to install without this.
  have python3 || pkgs+=(python3)
  python3 -m venv --help >/dev/null 2>&1 || pkgs+=(python3-venv)
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

  # --- Docker Engine + Compose v2 -------------------------------------------
  # Dockerised projects drive everything through `docker compose`, so the v2
  # plugin matters as much as the daemon: the standalone `docker-compose` (v1,
  # hyphen) is EOL and is not what `docker compose` resolves to. Hence the
  # two-part guard — a box can have the daemon and still fail every make target.
  if ! have docker || ! docker compose version >/dev/null 2>&1; then
    # shellcheck disable=SC1091
    . /etc/os-release 2>/dev/null || true
    distro="${ID:-}"
    # UBUNTU_CODENAME first, not VERSION_CODENAME: on a derivative the latter
    # is that distro's own codename (Mint 21 says 'vera'), which is not a suite
    # in Docker's Ubuntu repo. Derivatives set UBUNTU_CODENAME to the upstream
    # release for this reason, and on Ubuntu itself the two are identical.
    codename="${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}"
    case "$distro" in
      ubuntu | debian) ;;
      *)
        # Derivatives (Mint, Pop!_OS, Raspbian) report their own ID but track
        # an upstream release, which ID_LIKE names. Docker's repo only has
        # paths for the two upstreams.
        case "${ID_LIKE:-}" in
          *ubuntu*) distro=ubuntu ;;
          *debian*) distro=debian ;;
          *)        distro="" ;;
        esac
        ;;
    esac

    if [ -n "$distro" ] && [ -n "$codename" ]; then
      log "Installing Docker Engine + Compose v2 (docker.com repo)"
      $SUDO install -m 0755 -d /etc/apt/keyrings
      # --yes: gpg refuses to overwrite an existing -o target, which would make
      # a second run fail where the first succeeded.
      if curl -fsSL "https://download.docker.com/linux/$distro/gpg" |
           $SUDO gpg --batch --yes --dearmor -o /etc/apt/keyrings/docker.gpg; then
        $SUDO chmod a+r /etc/apt/keyrings/docker.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$distro $codename stable" |
          $SUDO tee /etc/apt/sources.list.d/docker.list >/dev/null
        $SUDO apt-get update -y
        $SUDO apt-get install -y docker-ce docker-ce-cli containerd.io \
          docker-buildx-plugin docker-compose-plugin || true
      fi
    fi

    # Fallback for a release Docker's repo doesn't carry. Older distros package
    # no Compose v2 at all, so this can leave the daemon without it — the note
    # below says so rather than letting `make build` be the one to find out.
    if ! have docker; then
      log "Docker's own repo unavailable — falling back to distro packages"
      $SUDO apt-get install -y docker.io || true
      $SUDO apt-get install -y docker-compose-v2 || true
    fi

    if have docker && ! docker compose version >/dev/null 2>&1; then
      log "note: Docker is installed but Compose v2 is not — 'docker compose' will"
      log "      fail. See https://docs.docker.com/compose/install/linux/"
    fi
  fi

  # Talking to the daemon socket otherwise needs sudo on every command.
  if have docker && [ -n "$SUDO" ] && ! id -nG | grep -qw docker; then
    log "Adding $(id -un) to the 'docker' group"
    if $SUDO usermod -aG docker "$(id -un)"; then
      log "  log out and back in (or run 'newgrp docker') for this to take effect"
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

# EDITOR and PATH for interactive shells (managed block, non-destructive).
# Both rc files: bash on a Linux box, zsh on macOS.
#
# The block carries a version. Matching on the bare "dotfiles managed" marker
# would make a re-run after a `git pull` a no-op on every machine that already
# has an older block, so new lines would only ever reach fresh boxes. Instead:
# skip if the current version is there, replace it if an older one is.
RC_BLOCK_VERSION=2
for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
  [ -f "$rc" ] || continue
  grep -qF ">>> dotfiles managed v${RC_BLOCK_VERSION} >>>" "$rc" && continue
  if grep -qF "dotfiles managed" "$rc"; then
    log "Replacing outdated managed block in $rc"
    # Range match on the two marker lines. -i with an attached suffix is the
    # one spelling both BSD (macOS) and GNU sed accept.
    sed -i".bak.$(date +%s)" '/dotfiles managed/,/dotfiles managed/d' "$rc"
  fi
  log "Adding managed block to $rc"
  # Unquoted heredoc so the version interpolates; $HOME and $PATH are escaped
  # so they stay literal and resolve when the shell starts, not now.
  cat >> "$rc" <<RC

# >>> dotfiles managed v${RC_BLOCK_VERSION} >>>
export EDITOR=nvim
export VISUAL=nvim
# uv and the Claude Code CLI install here
case ":\$PATH:" in
  *":\$HOME/.local/bin:"*) ;;
  *) export PATH="\$HOME/.local/bin:\$PATH" ;;
esac
# <<< dotfiles managed v${RC_BLOCK_VERSION} <<<
RC
done

# Commits fail outright without an identity, and it's per-machine state no
# repo can carry — so warn rather than guess, and never block on a prompt
# (this script runs unattended on codespace create).
if ! git config --global user.name >/dev/null || ! git config --global user.email >/dev/null; then
  log "note: git has no global user.name / user.email — commits will fail. Set them:"
  log "      git config --global user.name 'Your Name'"
  log "      git config --global user.email 'you@example.com'"
fi

# =============================================================================
# 3. Claude Code and uv — per-user installs, need no root on either OS
# =============================================================================

if ! have claude; then
  log "Installing Claude Code"
  curl -fsSL https://claude.ai/install.sh | bash ||
    log "Claude Code install failed (continuing) — see https://claude.com/claude-code"
fi

# uv is needed on the *host* even for a project that runs in Docker: test
# runners and pre-commit hooks fall back to `uv run` when the container is
# down, and the editor's Python LSP resolves imports against a host-side
# .venv — without one, every import in an otherwise healthy project is red.
# (Homebrew already covers this on macOS; this catches Linux and no-brew Macs.)
if ! have uv; then
  log "Installing uv"
  curl -LsSf https://astral.sh/uv/install.sh | sh ||
    log "uv install failed (continuing) — see https://docs.astral.sh/uv/"
fi

log "Done. Run 'nvim' — LazyVim installs plugins on first launch."
