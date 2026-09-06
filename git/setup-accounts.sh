#!/usr/bin/env bash
# Create and verify the machine-specific personal GitHub SSH key.
# This script is safe to rerun and never replaces an existing private key.
set -euo pipefail    # abort on an error, an unset variable, or a failing pipeline stage

LABEL=git-accounts    # the tag log() puts in front of every message
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"    # absolute path of this script's directory
source "$DIR/../install-lib.sh"    # pull in log, has, require_no_args, ...
require_no_args "$@"    # reject anything but an empty argument list or --help

SSH_DIR="$HOME/.ssh"    # where OpenSSH keeps per-user keys
PRIVATE_KEY="$SSH_DIR/id_ed25519_personal"    # this machine's key, named apart from any work key
PUBLIC_KEY="$PRIVATE_KEY.pub"    # ssh-keygen's own naming convention
EXPECTED_ACCOUNT=almon7    # the GitHub account the key must authenticate as
DOTFILES_DIR="$(cd "$DIR/.." && pwd)"    # the repository whose remote may be rewritten
SSH_REMOTE="git@github.com:$EXPECTED_ACCOUNT/dotfiles.git"    # the SSH form of that remote
AUTH_OUTPUT=''    # set by check_github_account: what GitHub replied
AUTH_ACCOUNT=''    # set by check_github_account: the account it named

has git || { log 'git is required; run git/install.sh first.'; exit 1; }    # needed to read and set the remote
has ssh-keygen || { log 'ssh-keygen is required; install OpenSSH first.'; exit 1; }    # needed to create the key
has ssh || { log 'ssh is required; install OpenSSH first.'; exit 1; }    # needed to verify it

mkdir -p "$SSH_DIR"    # OpenSSH does not create this itself
chmod 700 "$SSH_DIR"    # ssh refuses to use a directory others can read

if [ -f "$PRIVATE_KEY" ]; then    # a usable key is already here
  log "Keeping existing private key $PRIVATE_KEY"
elif [ -e "$PRIVATE_KEY" ]; then    # the path exists but is a directory, socket or such
  log "$PRIVATE_KEY exists but is not a regular file; refusing to replace it."
  exit 1
elif [ -e "$PUBLIC_KEY" ]; then    # half a key pair: the private half may be recoverable elsewhere
  log "$PUBLIC_KEY exists without its private key; refusing to replace it."
  exit 1
else
  if [ ! -t 0 ] || [ ! -t 1 ]; then    # ssh-keygen would block on its passphrase prompt
    log 'Skipping SSH-key creation because this is not an interactive terminal'
    exit 0
  fi

  response=''
  printf '\nSet up a personal GitHub SSH key now? [Y/n]: '
  IFS= read -r response || response=n    # a closed input counts as declining
  case "$response" in
    ''|y|Y|yes|YES) ;;    # Enter alone accepts
    *) log 'SSH-key setup skipped; the HTTPS remote remains available'; exit 0 ;;    # not an error
  esac

  log "Creating $PRIVATE_KEY"
  ssh-keygen -t ed25519 -C "$EXPECTED_ACCOUNT@github" -f "$PRIVATE_KEY"    # -C is the comment shown on GitHub
fi

chmod 600 "$PRIVATE_KEY"    # ssh refuses a private key others can read
if [ ! -f "$PUBLIC_KEY" ]; then    # the public half can always be derived again
  log 'Recreating the missing public key from the existing private key'
  if ! ssh-keygen -y -f "$PRIVATE_KEY" > "$PUBLIC_KEY"; then    # -y prints the public key
    log 'Could not recreate the public key; check its passphrase and try again.'
    exit 1
  fi
fi
chmod 644 "$PUBLIC_KEY"    # the public half is meant to be readable

# A passphrase-protected key must be available to the agent for unattended Git
# commands. When an agent is available, load the key once during setup.
if ! ssh-keygen -y -P '' -f "$PRIVATE_KEY" >/dev/null 2>&1 &&    # an empty passphrase fails: the key has one
   [ -n "${SSH_AUTH_SOCK:-}" ] && has ssh-add; then    # and an agent is running to hold it
  log 'Adding the passphrase-protected key to the SSH agent'
  ssh-add "$PRIVATE_KEY"    # prompts once, then Git runs unattended
fi

log 'Public-key fingerprint:'
ssh-keygen -lf "$PUBLIC_KEY"    # -l prints the fingerprint to compare against GitHub's

check_github_account() {
  local ssh_options    # built as an array so each option stays one argument
  AUTH_OUTPUT=''    # clear the previous attempt's results
  AUTH_ACCOUNT=''
  ssh_options=(
    -T    # no terminal: GitHub offers no shell anyway
    -o ConnectTimeout=10    # fail quickly on a dead network
    -o IdentitiesOnly=yes    # try this key alone, not every key the agent holds
    -o StrictHostKeyChecking=accept-new    # trust GitHub's host key on first contact
    -i "$PRIVATE_KEY"
  )
  [ -t 0 ] || ssh_options+=(-o BatchMode=yes)    # without a terminal, never prompt for a passphrase

  AUTH_OUTPUT="$(ssh "${ssh_options[@]}" git@github.com 2>&1 || true)"    # GitHub always exits non-zero here
  if [[ "$AUTH_OUTPUT" =~ Hi[[:space:]]([^!]+)! ]]; then    # "Hi <account>!" means the key was accepted
    AUTH_ACCOUNT=${BASH_REMATCH[1]}    # the text the regexp captured
    [ "$AUTH_ACCOUNT" = "$EXPECTED_ACCOUNT" ] && return 0    # 0: the right account
    return 2    # 2: authenticated, but as somebody else
  fi

  case "$AUTH_OUTPUT" in    # no greeting, so classify the failure
    *'Permission denied (publickey)'*) return 1 ;;    # 1: GitHub does not know this key yet
    *'Could not resolve hostname'*|*'Connection timed out'*|*'Operation timed out'*|\
    *'Network is unreachable'*|*'No route to host'*) return 3 ;;    # 3: GitHub was never reached
    *) return 4 ;;    # 4: something unrecognised
  esac
}

configure_dotfiles_remote() {
  local current_remote
  current_remote="$(git -C "$DOTFILES_DIR" remote get-url origin 2>/dev/null || true)"    # empty when there is no origin
  case "$current_remote" in
    "$SSH_REMOTE")
      log 'Dotfiles origin already uses personal SSH'    # nothing to change
      ;;
    "https://github.com/$EXPECTED_ACCOUNT/dotfiles.git"|\
    "https://github.com/$EXPECTED_ACCOUNT/dotfiles")    # the clone URL, with or without the suffix
      git -C "$DOTFILES_DIR" remote set-url origin "$SSH_REMOTE"    # now that the key works, push over SSH
      log 'Changed dotfiles origin from HTTPS to personal SSH'
      ;;
    '')
      log 'Dotfiles has no origin remote; leaving it unchanged'
      ;;
    *)
      log "Dotfiles origin is not the standard HTTPS URL; leaving it unchanged: $current_remote"    # a deliberate choice, probably
      ;;
  esac
}

handle_check_result() {
  local check_status=$1    # the status check_github_account returned
  case "$check_status" in
    0)
      configure_dotfiles_remote    # the key works, so the remote can rely on it
      log "GitHub authentication succeeded as $EXPECTED_ACCOUNT"
      return 0    # 0: done, the caller may exit
      ;;
    2)
      log "This key authenticates as $AUTH_ACCOUNT, not $EXPECTED_ACCOUNT; refusing to reuse it."
      return 2    # 2: a wrong account is not something waiting will fix
      ;;
    3)
      log 'GitHub could not be reached; leaving the current remote unchanged.'
      return 3    # 3: unreachable, so nothing was proved either way
      ;;
    4)
      log 'GitHub SSH verification failed for an unexpected reason:'
      printf '%s\n' "$AUTH_OUTPUT" >&2    # show what ssh actually said
      return 4    # 4: unrecognised
      ;;
    *) return 1 ;;    # 1: the key is simply not registered yet
  esac
}

check_status=0
if check_github_account; then    # the status is wanted, and set -e must not act on it
  check_status=0
else
  check_status=$?    # read it before the next command overwrites it
fi

if handle_check_result "$check_status"; then    # 0 means everything is in order
  exit 0
else
  handled_status=$?
  case "$handled_status" in
    2|4) exit 1 ;;    # a wrong account or an unknown failure: report it
    3) exit 0 ;;    # offline is not the user's mistake
  esac
fi

log "GitHub does not recognise this key as $EXPECTED_ACCOUNT yet."
printf '\nAdd this public key at https://github.com/settings/ssh/new:\n\n'
cat "$PUBLIC_KEY"    # print it for copying into that page

if [ ! -t 0 ] || [ ! -t 1 ]; then    # nobody is here to paste it
  printf '\nRun install.sh interactively after registering the key.\n'
  exit 0
fi

while true; do    # keep offering to re-check until it works or the user skips
  printf '\nPress Enter after adding the key to GitHub, or type s to skip: '
  response=''
  if ! IFS= read -r response; then    # input closed
    log 'Input closed; skipping GitHub verification'
    exit 0
  fi

  case "$response" in
    '') ;;    # Enter: fall through to the check below
    s|S|skip|SKIP)
      log 'GitHub verification skipped; rerun install.sh when ready'
      exit 0
      ;;
    *)
      log 'Press Enter to retry or type s to skip'
      continue    # anything else re-asks without spending a network round trip
      ;;
  esac

  check_status=0
  if check_github_account; then    # ask GitHub again
    check_status=0
  else
    check_status=$?
  fi

  if handle_check_result "$check_status"; then
    exit 0
  else
    handled_status=$?
    case "$handled_status" in
      2|4) exit 1 ;;    # as above: these will not improve by waiting
      3) exit 0 ;;
    esac
  fi

  log "GitHub still does not recognise the key as $EXPECTED_ACCOUNT"    # status 1: loop and offer another try
done
