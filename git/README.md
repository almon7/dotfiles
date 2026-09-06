# Git identity and GitHub SSH

Two different things get confused here, so start with the distinction:

- **Identity** is the name and email stamped into every commit. It is metadata
  — nothing verifies it, and anyone can write anything there.
- **Authentication** is proving to GitHub that you may push. That is the SSH
  key, and it is what actually gates anything.

`./install.sh git` sets up both.

## What the installer does

It links [`gitconfig`](gitconfig) to `~/.gitconfig`, the per-user config Git
reads for every repository. That file:

- sets the personal identity (`almon7`) for commits,
- points `core.editor` at `nvim`, so commit messages and interactive rebases
  open there,
- and selects the personal SSH key for every repository via `core.sshCommand`.

Whatever is already at `~/.gitconfig` — a real file, or a link pointing
somewhere else — is moved aside to a timestamped backup first, so nothing is
lost.

`~/.gitconfig.local` is included last and is never tracked here. "Included last"
matters: Git applies the last value it reads, so anything in that file overrides
the tracked config. Machine-specific settings and additional identities belong
there — see [Add another profile](#add-another-profile). A missing include is
harmless, so a fresh machine needs no extra setup.

## Enrolling the key with GitHub

On a new machine, clone over HTTPS, because the SSH key that would authorise an
SSH clone does not exist yet:

```sh
git clone https://github.com/almon7/dotfiles.git ~/dotfiles
~/dotfiles/install.sh
```

[`setup-accounts.sh`](setup-accounts.sh) then handles the key. What it
guarantees:

- **It creates `~/.ssh/id_ed25519_personal` only when it is missing**, and never
  replaces an existing private key — so rerunning it is safe.
- **A passphrase is optional.** Press Enter for none. If you set one, the key is
  added to a running SSH agent (the background process that holds a decrypted
  key in memory) so later Git commands do not stop to ask for it again.
- **It prints the public key's fingerprint** — a short hash of the key — so you
  can compare it against what GitHub shows.
- **It skips enrollment entirely on a non-interactive run**, unless a key is
  already there to verify.

Enrollment is optional: answer `n` to keep using HTTPS.

The remote rewrite is deliberately conservative. Once the key authenticates as
`almon7`, the installer switches this repository's `origin` from HTTPS to SSH —
but only that exact URL:

- an `origin` already on the personal SSH URL is left alone, there being nothing
  to convert,
- a missing `origin`, or any non-standard URL, is left unchanged,
- and a key that authenticates as some **other** GitHub account is reported and
  refused, rather than quietly reused.

If the key is new, register it:

1. Open <https://github.com/settings/ssh/new> while signed in as `almon7`.
2. Give the key a machine-specific title, such as `MacBook 2026`.
3. Paste the complete output of:

   ```sh
   cat ~/.ssh/id_ed25519_personal.pub
   ```

4. Return to the installer and press Enter. It verifies authentication and
   switches `origin` to SSH. Type `s` to skip; rerunning `~/dotfiles/install.sh`
   safely resumes later.

Two rules worth keeping:

- **Private keys never go in this repository.** The `.pub` half is meant to be
  published; the other half is a secret that belongs only on the machine that
  generated it.
- **One key per machine.** A lost laptop is then revoked by deleting one key
  from GitHub, instead of replacing keys everywhere.

## Add another profile

A second identity — work, say — should not be typed into every repository by
hand. Git can pick one by directory instead. Extra profiles are local machine
state, so none of this is tracked here.

Create the profile, `~/.gitconfig-work`:

```ini
[user]
    name = Your Name
    email = you@company.example

[core]
    sshCommand = ssh -i ~/.ssh/id_ed25519_work -o IdentitiesOnly=yes
```

`IdentitiesOnly=yes` is what stops SSH from offering your personal key first and
authenticating as the wrong account.

Then route it by directory from `~/.gitconfig.local`, which the shared config
includes last:

```ini
[includeIf "gitdir:~/code/work/"]
    path = ~/.gitconfig-work
```

`includeIf` applies only inside repositories under that path, so cloning into
`~/code/work/` is all it takes to get the work identity.

Generate and register that account's key:

```sh
ssh-keygen -t ed25519 -C "you@company.example" -f ~/.ssh/id_ed25519_work
cat ~/.ssh/id_ed25519_work.pub
```

Add the public key to that GitHub account, authorising organisation SSO if it is
required, then confirm a repository resolves the profile you expect:

```sh
git -C ~/code/work/example config --show-origin --get user.email
git -C ~/code/work/example config --show-origin --get core.sshCommand
```

`--show-origin` prints which file each value came from, which is the quick way
to see whether the `includeIf` fired.
