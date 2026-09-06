# Setting up a VPS

For running Claude Code on a server rather than a laptop that overheats. A fresh
box accepts password logins from the entire internet, so these are the steps to
take *before* the [quick start](../README.md#quick-start) installs anything,
plus the operational notes that go with running work on a machine you only reach
over SSH. Assumes a fresh Debian/Ubuntu install.

On OVHcloud specifically:

- **There is no user to create.** Root SSH login is disabled and the login user
  is named after the distro (`ubuntu`, `debian`, `rocky`), already in the sudo
  group.
- **The temporary password arrives as a single-use secret link**, and you are
  prompted to change it on first login.
- **Keep the new one.** It is your `sudo` password, and your way back in via the
  KVM console — the provider's out-of-band screen-and-keyboard — if you ever
  break SSH.

## 1. Key-based login

A key pair is stronger than a password because the secret half never leaves your
laptop; the server only ever sees the public half. From your laptop, once you can
log in with the password:

```sh
ssh-copy-id -i ~/.ssh/id_ed25519.pub ubuntu@203.0.113.10
ssh ubuntu@203.0.113.10        # must not prompt for a password
```

That second line is the test, not a formality: password auth is turned off in
the next step, so a key that does not work yet locks you out.

Then add a host block to `~/.ssh/config` on your laptop, so later steps are just
`ssh vps`:

```sshconfig
Host vps
    HostName 203.0.113.10
    User ubuntu
    IdentityFile ~/.ssh/id_ed25519
    ForwardAgent yes
    LocalForward 8000 localhost:8000
    ServerAliveInterval 30
```

- `ForwardAgent yes` lets the server borrow your local key for its own
  git pushes — see the note under [Reaching the server](#reaching-the-server).
- `LocalForward` is how you reach a service on the box from your laptop browser
  without opening a port, also below.
- `ServerAliveInterval 30` sends a keepalive twice a minute so an idle
  connection is not silently dropped.

## 2. Turn off password authentication

Only once key login works, and **keep your current session open** until a fresh
one succeeds — a bad config here leaves the KVM console as the only way back.

The trap is worth understanding before you write anything:

- `sshd_config` starts with `Include /etc/ssh/sshd_config.d/*.conf`.
- Those files are read in lexical order, and for each keyword **the first value
  obtained wins** — the opposite of the last-wins convention every other `.d`
  directory uses.
- Cloud images commonly ship `50-cloud-init.conf` setting
  `PasswordAuthentication yes`. A file named `99-hardening.conf` is therefore
  read *after* it and silently ignored. No error, and passwords stay on.

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

- `KbdInteractiveAuthentication no` is the line people forget. Without it PAM
  can still offer a password-shaped prompt through a different mechanism.
- `PermitRootLogin no` is redundant on OVH, which disables it already.
- `sshd -t` tests the config before the restart, so a typo fails safely.

Then verify the *effective* config rather than reasoning about file order:

```sh
sudo sshd -T | grep -E 'passwordauthentication|kbdinteractive'
```

`sshd -T` prints the resolved configuration after every include and precedence
rule is applied. It is the only check that actually settles it.

> Ubuntu has used systemd **socket activation** for SSH since 22.10 — systemd
> owns the listening port and starts sshd on demand. For authentication changes
> `systemctl restart ssh` is fine, but changing `Port` or `ListenAddress` needs
> `systemctl daemon-reload && systemctl restart ssh.socket`, because the socket
> unit owns the listener, not sshd.

## 3. Firewall and swap

```sh
sudo ufw default deny incoming && sudo ufw default allow outgoing
sudo ufw allow OpenSSH && sudo ufw enable

free -h && swapon --show          # skip the rest if the image already has swap
sudo fallocate -l 2G /swapfile && sudo chmod 600 /swapfile
sudo mkswap /swapfile && sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

- **The firewall leaves only SSH open.** Everything you run is reached through
  an SSH tunnel instead of being published to the internet.
- **Swap is disk standing in for memory.** A small VPS running a compiler and a
  language server will otherwise hit the out-of-memory killer, which kills the
  biggest process — usually the one you cared about.
- **The `fstab` line makes it survive a reboot**; `swapon` alone lasts until the
  machine restarts.
- `fallocate` is fine on ext4. On btrfs it produces a swapfile the kernel
  rejects — use `dd` there.

## 4. Install the dotfiles

Follow the VPS half of the [quick start](../README.md#quick-start), then confirm
the packages landed:

```sh
nvim --version && tmux -V
```

## Reaching the server

Nothing needs to be published. `ssh -L 8000:localhost:8000 vps` opens port 8000
on your laptop and forwards it to `localhost:8000` **as seen from the server**,
so `http://localhost:8000` in your browser hits the service there. Put the
`LocalForward` lines in `~/.ssh/config` and plain `ssh vps` brings them up.

Two limits to know:

- **The tunnel lives in your laptop's SSH client**, so it dies with the
  connection and returns on reconnect. tmux protects the server-side processes,
  not the forward.
- **It is inbound-only.** An external service that needs to POST to your box — a
  webhook — needs a real public endpoint, not a tunnel.

> **Agent forwarding.** `ForwardAgent yes` lets the server use your laptop's SSH
> agent for its own authentication, so git pushes from the box are signed by
> your local key without the key ever being there. Never copy a private key onto
> a VPS.

## Docker

Install Docker Engine and the **Compose v2 plugin** separately on Linux; the
dotfiles installers do not manage them. A box can have a working daemon and
still fail every `docker compose` command, so check both. If your installation
adds you to the `docker` group, start a new login (or run `newgrp docker`)
before using the socket without `sudo` — group membership is only read at login.

> **A firewall does not cover published Docker ports.** Traffic to a published
> port is DNAT'd in `PREROUTING` and then traverses the `FORWARD` chain — it
> never reaches `INPUT`, which is where ufw's default-deny lives. ufw is not
> overridden, it simply is not consulted: `ufw deny 5432` has no effect on a
> container published with `-p 5432:5432`, and the port is open to the internet.
> Publish to loopback instead (`127.0.0.1:5432:5432`) and reach it over an SSH
> tunnel. Where a port genuinely must be public, the supported hook is Docker's
> `DOCKER-USER` chain, evaluated before Docker's own rules;
> [`ufw-docker`](https://github.com/chaifeng/ufw-docker) wires ufw into it. This
> bites hardest with a compose file that publishes a database on default
> credentials.

> **Docker on macOS** is Docker Desktop (or OrbStack/Colima) — a GUI app with a
> Linux VM behind it, not something to install unattended from a shell script.
> The dotfiles installers do not manage it; install it separately if needed.

### Working on a Dockerised Python project

A project whose test runner and linters live inside the container still wants
tooling on the host. Three things are not obvious:

```sh
cp sample.env .env    # compose interpolates ${UID}/${GID} from here, not the shell
uv sync --dev         # host-side .venv, so nvim's LSP can resolve imports
```

- **`.env` is not optional** if `compose.yaml` interpolates `${UID}`/`${GID}` to
  make container files owned by you. Bash sets `UID` but does not export it, so
  Compose cannot see it — without the file both resolve to empty and the image
  build fails on `groupadd -g ""`.
- **The host `.venv` is what the editor reads.** basedpyright resolves imports
  against the host filesystem, not the container, so without one every import in
  an otherwise healthy project shows up red. The venv exists for the language
  server; the tests still run in Docker.
- **`uv` on the host also backs the fallback paths** — pre-commit hooks that
  shell out to `uv run` when the container is not up, and e2e suites that drive
  the stack from outside it.
