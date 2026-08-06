# dotfiles

My personal dev-environment config, and an installer that reproduces it on a
Mac, a Debian/Ubuntu VPS, or a GitHub Codespace.

## Contents

| Path | What it is |
|---|---|
| [`nvim/`](nvim/README.md) | Neovim config (LazyVim). See its README for manual, per-OS setup. |
| [`tmux/`](tmux/tmux.conf) | tmux config — `C-a` prefix, vim-style keys, truecolor. |
| [`install.sh`](install.sh) | One-shot environment installer (macOS / Debian / Ubuntu / Codespaces). |
| `vscode_coding_profile.code-profile` | Exported VS Code profile. |

`install.sh` is split in two halves: **packages**, which are OS-specific and
need a package manager (Homebrew on macOS, apt on Debian/Ubuntu), and
**configs** — the symlinks, git settings and `EDITOR` — which are portable and
always run. A box where you can't install anything still gets working configs.
It's idempotent, so re-running it after a `git pull` is the normal way to
update a machine.

## Install

### GitHub Codespaces (automatic)

`install.sh` sets up the whole environment: recent **Neovim** + the config,
the tools it needs (**ripgrep**, **fd**, a C compiler), **lazygit**, the
**Claude Code** CLI, `git` editor → `nvim`, and `EDITOR=nvim`.

To run it automatically when you **create** a codespace:

1. Go to **[github.com/settings/codespaces](https://github.com/settings/codespaces)**
   → **Dotfiles** → tick **"Automatically install dotfiles"** (it uses this repo).
2. **Create a new codespace.** (Toggling the setting does *not* affect existing
   codespaces, and rebuilding one does *not* pick dotfiles up — see below.)

**Persistence — important:** personal dotfiles run **only when a codespace is
first created**, *not* on rebuild and *not* on stop/start.

- **Stop → Start** keeps the whole container, so nvim and everything else stay put.
- **Rebuild** re-runs the devcontainer (image + features + `postCreateCommand`)
  but **not** your dotfiles — a rebuilt codespace loses dotfiles-installed tools.
- To make the setup survive **rebuilds** too, run the installer from the project's
  devcontainer — `postCreateCommand` runs on create *and* rebuild:
  ```json
  {
    "postCreateCommand": "git clone https://github.com/almon7/dotfiles ~/dotfiles 2>/dev/null; bash ~/dotfiles/install.sh"
  }
  ```
  Only do this in repos that are **yours** — it installs your setup for anyone
  who opens them.

> **Fonts are client-side.** In a codespace the terminal font is rendered by your
> local VS Code / browser, so set a [Nerd Font](https://www.nerdfonts.com) in
> VS Code's `terminal.integrated.fontFamily` — installing one in the container
> does nothing.

### Remote VPS

For running Claude Code on a server rather than a laptop that overheats.
Assumes a fresh Debian/Ubuntu box where your SSH key already works.

```sh
sudo apt update && sudo apt install -y git   # minimal images may not ship it
git clone https://github.com/almon7/dotfiles ~/dotfiles && bash ~/dotfiles/install.sh
```

The installer needs `sudo` for the package half. OVH disables SSH login *as*
root but puts the distro user in the sudo group, so this works — check with
`sudo -n true` if unsure. Without sudo it skips the packages and still links
the configs.

Before that, on the server: add swap, enable a firewall, and turn off password
authentication. On OVHcloud note that root is disabled and the login user is
named after the distro (`ubuntu`, `debian`, `rocky`) — it is created for you, so
there is no user to add.

> **Agent forwarding.** Put `ForwardAgent yes` in the host's `~/.ssh/config`
> block on your laptop so git pushes from the server are signed by your local
> key. Never copy a private key onto a VPS.

### Local machine (macOS or Linux)

Clone and run the same installer. On macOS it uses Homebrew — install that
first from [brew.sh](https://brew.sh) — and additionally sets up the Xcode
Command Line Tools (Treesitter needs a C compiler) and a Nerd Font.

```sh
git clone git@github.com:almon7/dotfiles.git ~/dotfiles && ~/dotfiles/install.sh
```

Afterwards set the Nerd Font as your terminal font, and see
[`nvim/README.md`](nvim/README.md) for `:Copilot auth` and the rest of the
first-launch steps. That README also covers doing all of this by hand, which is
the path for Windows, Arch and Fedora — the installer doesn't cover those.

### Claude Code per-project (optional)

Dotfiles install Claude Code for **you** in all your codespaces. If you also want
a specific repo to ship it to **anyone** who opens it (teammates, CI), add the
maintained feature to that repo's `.devcontainer/devcontainer.json`:

```json
{
  "features": {
    "ghcr.io/anthropics/devcontainer-features/claude-code:1": {}
  }
}
```

Having it in both places is harmless — it just installs once from each.

## tmux

Everything on a remote box runs inside tmux, so a dropped connection or a closed
laptop doesn't kill the work. Claude Code keeps running while you're on a train.

```sh
tmux new -s dev          # start
tmux a -t dev            # come back to it
tmux ls                  # what's running
```

The prefix is **`C-a`** (remapped from the default `C-b`, which is a bad key).
Press it, release, then press the command key.

| Key | Does |
|---|---|
| `C-a d` | Detach — everything keeps running server-side |
| `C-a c` | New window (a tab) |
| `C-a 1`…`9` | Jump to window N |
| `C-a n` / `C-a p` | Next / previous window |
| `C-a ,` | Rename the current window |
| `C-a w` | Pick a window from a list |
| `C-a &` | Close the current window |
| <code>C-a &#124;</code> / `C-a -` | Split vertically / horizontally |
| `C-a h/j/k/l` | Move between panes |
| `C-h/j/k/l` | Move between panes **and** Neovim splits (no prefix) |
| `C-a z` | Zoom current pane fullscreen (toggle) |
| `C-a [` | Scrollback / copy mode — vim keys, `q` to exit |
| `C-a r` | Reload this config after editing it |
| `C-a ?` | List every binding |

That's the whole working set. The mouse is enabled too: drag borders to resize,
scroll wheel for history.

A typical layout: window 1 for `nvim`, window 2 for `claude`, window 3 for git
and test runs. Give Claude a task, `C-a 1` back to the editor while it works.

> **Colors.** The config sets `default-terminal` and truecolor overrides because
> the Catppuccin/Tokyonight setup uses `transparent = true` — without them the
> colorscheme renders wrong inside tmux.

### Copy and paste

Four separate mechanisms, which is why this trips people up:

| Want | Do |
|---|---|
| Copy text off the screen | `C-a [`, move to the start, `v`, select, `y` |
| Paste from the system clipboard | `Cmd-V` (macOS) / `Ctrl-Shift-V` (Linux) |
| Paste what you just yanked in tmux | `C-a ]` |
| Select with the mouse | Hold **Shift** while dragging, then `Cmd-C` |

`mode-keys vi` on its own does *not* give you vim's `v`/`y` — tmux leaves `y`
unbound and puts `v` on rectangle-toggle. The config binds them properly;
rectangle select moves to `C-v`.

The Shift-drag is needed because `mouse on` makes tmux capture the mouse, so a
plain drag selects into tmux's buffer rather than the terminal's. Shift tells
WezTerm to bypass tmux and do a native selection.

> **Over SSH.** `set-clipboard on` sends yanks to your laptop's clipboard via
> OSC 52, so `y` in copy mode and `"+y` in Neovim both reach it. Needs a
> terminal that supports OSC 52 (WezTerm, Kitty, Ghostty, iTerm2). Copy only —
> most terminals refuse an OSC 52 *read*, so paste stays on `Cmd-V`.

> **Clear screen.** `C-l` is taken over for pane navigation, so the shell's
> clear-screen moves to `C-a C-l`.

> **Autosave.** `focus-events on` is required: [`autosave.lua`](nvim/lua/config/autosave.lua)
> hooks `FocusLost`/`FocusGained`, and tmux swallows those events by default.
