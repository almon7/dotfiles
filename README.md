# dotfiles

My personal dev-environment config, and an installer that reproduces it on a
Mac, a Debian/Ubuntu VPS, or a GitHub Codespace.

## Contents

| Path | What it is |
|---|---|
| [`git/`](git/install.sh) | Git installer, Neovim editor default, and identity check. |
| [`hunk/`](hunk/install.sh) | Hunk terminal diff viewer installer. |
| [`nvim/`](nvim/README.md) | Neovim config and its self-contained installer. |
| [`tmux/`](tmux/tmux.conf) | tmux config and installer — `C-a` prefix, vim-style keys, truecolor. |
| [`wezterm/`](wezterm/.wezterm.lua) | WezTerm keyboard/font config and installer. |
| [`install.sh`](install.sh) | Interactive launcher for the installers above. |

Run `./install.sh` to choose configs from an interactive checklist. You can also
install everything with `./install.sh --all`, or name only what you want, such
as `./install.sh nvim tmux`. Every folder has an independent installer. Package
installation uses Homebrew on both macOS and Linux whenever a formula is
available. WezTerm is the exception because its Homebrew cask is macOS-only.
All scripts are idempotent. Non-interactive runs install all components
automatically.

### What it installs

| What | Why |
|---|---|
| **Neovim** (recent) + this config | the editor |
| **ripgrep**, **fd**, a C compiler, **Node** | what the Neovim config needs |
| **Python** | Mason installs the Python LSP from PyPI via `python3 -m venv` |
| **tmux** + this config | so a dropped SSH connection doesn't kill the work |
| **JetBrainsMono Nerd Font** | Neovim icons (automatic on macOS with Neovim) |
| **WezTerm** | terminal (automatic on macOS with WezTerm) |
| **Git**, editor → `nvim` | version control and its editor default |
| **Hunk** | terminal UI for reviewing diffs and agent-authored changes |

It does *not* set `git config user.name` / `user.email` — that's per-machine
state no repo can carry. The Git installer warns when either value is missing
rather than guessing.

## Install

### GitHub Codespaces (automatic)

`install.sh` sets up the whole environment — see
[What it installs](#what-it-installs). To run it automatically when you
**create** a codespace:

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
Assumes a fresh Debian/Ubuntu box.

On OVHcloud, root SSH login is disabled and the login user is named after the
distro (`ubuntu`, `debian`, `rocky`) — it is created for you and is in the sudo
group, so there is no user to add. The temporary password arrives as a
single-use secret link, and **you are prompted to change it on first login**.
Keep the new one: it's your `sudo` password, and your way back in via the KVM
console if you ever break SSH.

#### 1. Key-based login

From your laptop, once you can log in with the password:

```sh
ssh-copy-id -i ~/.ssh/id_ed25519.pub ubuntu@203.0.113.10
ssh ubuntu@203.0.113.10        # must not prompt for a password
```

Then add a host block on your laptop, so later steps are just `ssh vps`:

```
Host vps
    HostName 203.0.113.10
    User ubuntu
    IdentityFile ~/.ssh/id_ed25519
    ForwardAgent yes
    LocalForward 8000 localhost:8000
    ServerAliveInterval 30
```

`LocalForward` is how you reach a service on the box from your laptop browser
without opening a port — see [Reaching the server](#reaching-the-server).

#### 2. Turn off password authentication

Only once key login works, and **keep your current session open** until a fresh
one succeeds — a bad config here leaves the KVM console as the only way back.

The trap: `sshd_config` starts with `Include /etc/ssh/sshd_config.d/*.conf`,
those files are read in lexical order, and for each keyword **the first value
obtained wins** — the opposite of the last-wins convention every other `.d`
directory uses. Cloud images commonly ship `50-cloud-init.conf` setting
`PasswordAuthentication yes`, so a file named `99-hardening.conf` is read after
it and silently ignored. No error, and passwords stay on.

So look before writing, rather than guessing a prefix:

```sh
ls /etc/ssh/sshd_config.d/
sudo grep -rE 'PasswordAuthentication|KbdInteractive' /etc/ssh/sshd_config /etc/ssh/sshd_config.d/
```

Write a file that sorts *before* anything already setting these:

```sh
sudo tee /etc/ssh/sshd_config.d/10-hardening.conf >/dev/null <<'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
EOF
sudo sshd -t && sudo systemctl restart ssh
```

`KbdInteractiveAuthentication no` is the line people forget: without it PAM can
still offer a password-shaped prompt. `PermitRootLogin no` is redundant on OVH,
which disables it already.

Then verify the *effective* config rather than reasoning about file order:

```sh
sudo sshd -T | grep -E 'passwordauthentication|kbdinteractive'
```

`sshd -T` prints the resolved configuration after all includes and precedence
are applied. It is the only check that actually settles it.

> Ubuntu has used systemd **socket activation** for SSH since 22.10. For
> authentication changes `systemctl restart ssh` is fine, but changing `Port`
> or `ListenAddress` needs `systemctl daemon-reload && systemctl restart
> ssh.socket` — the socket unit owns the listener, not sshd.

#### 3. Firewall and swap

```sh
sudo ufw default deny incoming && sudo ufw default allow outgoing
sudo ufw allow OpenSSH && sudo ufw enable

free -h && swapon --show          # skip the rest if the image already has swap
sudo fallocate -l 2G /swapfile && sudo chmod 600 /swapfile
sudo mkswap /swapfile && sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

Only SSH is open; everything else is reached through the tunnel. (`fallocate`
is fine on ext4. On btrfs it produces a swapfile the kernel rejects — use `dd`
there.)

#### 4. Install

```sh
sudo apt-get update
sudo apt-get install -y build-essential procps curl file git
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
git clone https://github.com/almon7/dotfiles ~/dotfiles
bash ~/dotfiles/install.sh
```

The `apt-get` packages are Homebrew's Linux prerequisites; the dotfiles
installer itself installs supported tools exclusively through Homebrew. Add the
`brew shellenv` line printed by Homebrew's installer to your shell profile so
`brew` and its packages remain on `PATH` in future sessions.

Afterwards, set your git identity — the scripts deliberately don't guess it:

```sh
git config --global user.name "Your Name"
git config --global user.email "you@example.com"
nvim --version && tmux -V                 # confirm the selected packages landed
```

#### Reaching the server

Nothing needs to be published. `ssh -L 8000:localhost:8000 vps` opens port 8000
on your laptop and forwards it to `localhost:8000` **as seen from the server**,
so `http://localhost:8000` in your browser hits the container. Put the
`LocalForward` lines in `~/.ssh/config` and plain `ssh vps` brings them up.

The tunnel lives in your laptop's SSH client, so it dies with the connection and
returns on reconnect — tmux protects the server-side processes, not the forward.
It is also inbound-only: an external service that needs to POST to your box (a
webhook) needs a real public endpoint, not a tunnel.

> **Agent forwarding.** Put `ForwardAgent yes` in the host's `~/.ssh/config`
> block on your laptop so git pushes from the server are signed by your local
> key. Never copy a private key onto a VPS.

> **A firewall does not cover published Docker ports.** Traffic to a published
> port is DNAT'd in `PREROUTING` and then traverses the `FORWARD` chain — it
> never reaches `INPUT`, which is where ufw's default-deny lives. ufw isn't
> overridden, it simply isn't consulted: `ufw deny 5432` has no effect on a
> container published with `-p 5432:5432`, and the port is open to the
> internet. Publish to loopback instead (`127.0.0.1:5432:5432`) and reach it
> over an SSH tunnel. Where a port genuinely must be public, the supported hook
> is Docker's `DOCKER-USER` chain, which is evaluated before its own rules;
> [`ufw-docker`](https://github.com/chaifeng/ufw-docker) wires ufw into it.
> This bites hardest with a compose file that publishes a database on default
> credentials.

### Local machine (macOS or Linux)

Install [Homebrew](https://brew.sh), then clone and run the same installer. On
macOS it additionally sets up the Xcode Command Line Tools (Treesitter needs a
C compiler) and a Nerd Font.

```sh
git clone git@github.com:almon7/dotfiles.git ~/dotfiles && ~/dotfiles/install.sh
```

Afterwards set the Nerd Font as your terminal font, and see
[`nvim/README.md`](nvim/README.md) for `:Copilot auth` and the rest of the
first-launch steps. That README also covers doing all of this by hand, which is
the path for Windows, Arch and Fedora — the installer doesn't cover those.

> **Docker on macOS** is Docker Desktop (or OrbStack/Colima) — a GUI app with a
> VM behind it, not something to install unattended from a shell script. The
> dotfiles installers do not manage Docker; install it separately if needed.

### Claude Code per-project (optional)

The dotfiles installers do not install Claude Code. To have a specific repo ship
it to **anyone** who opens it (teammates, CI), add the maintained feature to that
repo's `.devcontainer/devcontainer.json`:

```json
{
  "features": {
    "ghcr.io/anthropics/devcontainer-features/claude-code:1": {}
  }
}
```

## Docker

Install Docker Engine and the **Compose v2 plugin** separately on Linux; the
dotfiles installers do not manage them. A box can have a working daemon and
still fail every `docker compose` command, so check both. If your installation
adds you to the `docker` group, start a new login (or run `newgrp docker`) before
using the socket without `sudo`.

### Working on a Dockerised Python project

A project whose test runner and linters live inside the container still wants
tooling on the host. Three things aren't obvious:

```sh
cp sample.env .env    # compose interpolates ${UID}/${GID} from here, not the shell
uv sync --dev         # host-side .venv, so nvim's LSP can resolve imports
```

- **`.env` is not optional** if `compose.yaml` interpolates `${UID}`/`${GID}`.
  Bash sets `UID` but doesn't export it, so Compose can't see it — without the
  file both resolve to empty and the image build fails on `groupadd -g ""`.
- **The host `.venv` is what the editor reads.** basedpyright resolves imports
  against the host filesystem, not the container, so without one every import
  in an otherwise healthy project shows up red. The venv is for the LSP; the
  tests still run in Docker.
- **`uv` on the host also backs the fallback paths** — pre-commit hooks that
  shell out to `uv run` when the container isn't up, and e2e suites that drive
  the stack from outside it.

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
