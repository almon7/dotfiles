#!/usr/bin/env bash
# Create and verify the machine-specific personal GitHub SSH key.
# This script is safe to rerun and never replaces an existing private key.
set -euo pipefail

LABEL=git-accounts
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../install-lib.sh"
require_no_args "$@"

SSH_DIR="$HOME/.ssh"
PRIVATE_KEY="$SSH_DIR/id_ed25519_personal"
PUBLIC_KEY="$PRIVATE_KEY.pub"
EXPECTED_ACCOUNT=almon7
DOTFILES_DIR="$(cd "$DIR/.." && pwd)"
SSH_REMOTE="git@github.com:$EXPECTED_ACCOUNT/dotfiles.git"
AUTH_OUTPUT=''
AUTH_ACCOUNT=''

has git || { log 'git is required; run git/install.sh first.'; exit 1; }
has ssh-keygen || { log 'ssh-keygen is required; install OpenSSH first.'; exit 1; }
has ssh || { log 'ssh is required; install OpenSSH first.'; exit 1; }

mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"

if [ -f "$PRIVATE_KEY" ]; then
  log "Keeping existing private key $PRIVATE_KEY"
elif [ -e "$PRIVATE_KEY" ]; then
  log "$PRIVATE_KEY exists but is not a regular file; refusing to replace it."
  exit 1
elif [ -e "$PUBLIC_KEY" ]; then
  log "$PUBLIC_KEY exists without its private key; refusing to replace it."
  exit 1
else
  if [ ! -t 0 ] || [ ! -t 1 ]; then
    log 'Skipping SSH-key creation because this is not an interactive terminal'
    exit 0
  fi

  response=''
  printf '\nSet up a personal GitHub SSH key now? [Y/n]: '
  IFS= read -r response || response=n
  case "$response" in
    ''|y|Y|yes|YES) ;;
    *) log 'SSH-key setup skipped; the HTTPS remote remains available'; exit 0 ;;
  esac

  log "Creating $PRIVATE_KEY"
  ssh-keygen -t ed25519 -C "$EXPECTED_ACCOUNT@github" -f "$PRIVATE_KEY"
fi

chmod 600 "$PRIVATE_KEY"
if [ ! -f "$PUBLIC_KEY" ]; then
  log 'Recreating the missing public key from the existing private key'
  if ! ssh-keygen -y -f "$PRIVATE_KEY" > "$PUBLIC_KEY"; then
    log 'Could not recreate the public key; check its passphrase and try again.'
    exit 1
  fi
fi
chmod 644 "$PUBLIC_KEY"

# A passphrase-protected key must be available to the agent for unattended Git
# commands. When an agent is available, load the key once during setup.
if ! ssh-keygen -y -P '' -f "$PRIVATE_KEY" >/dev/null 2>&1 &&
   [ -n "${SSH_AUTH_SOCK:-}" ] && has ssh-add; then
  log 'Adding the passphrase-protected key to the SSH agent'
  ssh-add "$PRIVATE_KEY"
fi

log 'Public-key fingerprint:'
ssh-keygen -lf "$PUBLIC_KEY"

check_github_account() {
  local ssh_options
  AUTH_OUTPUT=''
  AUTH_ACCOUNT=''
  ssh_options=(
    -T
    -o ConnectTimeout=10
    -o IdentitiesOnly=yes
    -o StrictHostKeyChecking=accept-new
    -i "$PRIVATE_KEY"
  )
  [ -t 0 ] || ssh_options+=(-o BatchMode=yes)

  AUTH_OUTPUT="$(ssh "${ssh_options[@]}" git@github.com 2>&1 || true)"
  if [[ "$AUTH_OUTPUT" =~ Hi[[:space:]]([^!]+)! ]]; then
    AUTH_ACCOUNT=${BASH_REMATCH[1]}
    [ "$AUTH_ACCOUNT" = "$EXPECTED_ACCOUNT" ] && return 0
    return 2
  fi

  case "$AUTH_OUTPUT" in
    *'Permission denied (publickey)'*) return 1 ;;
    *'Could not resolve hostname'*|*'Connection timed out'*|*'Operation timed out'*|\
    *'Network is unreachable'*|*'No route to host'*) return 3 ;;
    *) return 4 ;;
  esac
}

configure_dotfiles_remote() {
  local current_remote
  current_remote="$(git -C "$DOTFILES_DIR" remote get-url origin 2>/dev/null || true)"
  case "$current_remote" in
    "$SSH_REMOTE")
      log 'Dotfiles origin already uses personal SSH'
      ;;
    "https://github.com/$EXPECTED_ACCOUNT/dotfiles.git"|\
    "https://github.com/$EXPECTED_ACCOUNT/dotfiles")
      git -C "$DOTFILES_DIR" remote set-url origin "$SSH_REMOTE"
      log 'Changed dotfiles origin from HTTPS to personal SSH'
      ;;
    '')
      log 'Dotfiles has no origin remote; leaving it unchanged'
      ;;
    *)
      log "Dotfiles origin is not the standard HTTPS URL; leaving it unchanged: $current_remote"
      ;;
  esac
}

handle_check_result() {
  local check_status=$1
  case "$check_status" in
    0)
      configure_dotfiles_remote
      log "GitHub authentication succeeded as $EXPECTED_ACCOUNT"
      return 0
      ;;
    2)
      log "This key authenticates as $AUTH_ACCOUNT, not $EXPECTED_ACCOUNT; refusing to reuse it."
      return 2
      ;;
    3)
      log 'GitHub could not be reached; leaving the current remote unchanged.'
      return 3
      ;;
    4)
      log 'GitHub SSH verification failed for an unexpected reason:'
      printf '%s\n' "$AUTH_OUTPUT" >&2
      return 4
      ;;
    *) return 1 ;;
  esac
}

check_status=0
if check_github_account; then
  check_status=0
else
  check_status=$?
fi

if handle_check_result "$check_status"; then
  exit 0
else
  handled_status=$?
  case "$handled_status" in
    2|4) exit 1 ;;
    3) exit 0 ;;
  esac
fi

log "GitHub does not recognise this key as $EXPECTED_ACCOUNT yet."
printf '\nAdd this public key at https://github.com/settings/ssh/new:\n\n'
cat "$PUBLIC_KEY"

if [ ! -t 0 ] || [ ! -t 1 ]; then
  printf '\nRun install.sh interactively after registering the key.\n'
  exit 0
fi

while true; do
  printf '\nPress Enter after adding the key to GitHub, or type s to skip: '
  response=''
  if ! IFS= read -r response; then
    log 'Input closed; skipping GitHub verification'
    exit 0
  fi

  case "$response" in
    '') ;;
    s|S|skip|SKIP)
      log 'GitHub verification skipped; rerun install.sh when ready'
      exit 0
      ;;
    *)
      log 'Press Enter to retry or type s to skip'
      continue
      ;;
  esac

  check_status=0
  if check_github_account; then
    check_status=0
  else
    check_status=$?
  fi

  if handle_check_result "$check_status"; then
    exit 0
  else
    handled_status=$?
    case "$handled_status" in
      2|4) exit 1 ;;
      3) exit 0 ;;
    esac
  fi

  log "GitHub still does not recognise the key as $EXPECTED_ACCOUNT"
done
