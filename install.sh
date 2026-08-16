#!/usr/bin/env bash
# Interactive launcher for the self-contained installers in each config folder.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() { printf '\033[1;34m[dotfiles]\033[0m %s\n' "$*"; }
usage() {
  cat <<'EOF'
Usage: ./install.sh [--all] [--config-only] [name ...]

With no arguments, shows an interactive checklist. In a non-interactive shell,
all available configs are installed to support Codespaces and bootstrap scripts.

  --all          install every available config
  --config-only  create config links without installing packages
  --list         list the available configs
  -h, --help     show this help

You can also run a config installer directly, for example ./tmux/install.sh.
EOF
}

names=()
scripts=()
descriptions=()
for script in "$ROOT"/*/install.sh; do
  [ -f "$script" ] || continue
  name="$(basename "$(dirname "$script")")"
  description="$(bash "$script" --description 2>/dev/null)"
  [ -n "$description" ] || description="$name configuration"
  names+=("$name")
  scripts+=("$script")
  descriptions+=("$description")
done

if [ "${#scripts[@]}" -eq 0 ]; then
  log "No installers found (expected */install.sh)."
  exit 1
fi

config_only=false
install_all=false
list_only=false
requested=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --all) install_all=true ;;
    --config-only) config_only=true ;;
    --list) list_only=true ;;
    -h|--help) usage; exit 0 ;;
    --*) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    *) requested+=("$1") ;;
  esac
  shift
done

if $list_only; then
  for ((i = 0; i < ${#names[@]}; i++)); do
    printf '%-12s %s\n' "${names[$i]}" "${descriptions[$i]}"
  done
  exit 0
fi

selected=()
for ((i = 0; i < ${#names[@]}; i++)); do selected+=(1); done

if [ "${#requested[@]}" -gt 0 ]; then
  for ((i = 0; i < ${#selected[@]}; i++)); do selected[$i]=0; done
  for wanted in "${requested[@]}"; do
    found=false
    for ((i = 0; i < ${#names[@]}; i++)); do
      if [ "$wanted" = "${names[$i]}" ]; then
        selected[$i]=1
        found=true
        break
      fi
    done
    if ! $found; then
      printf "Unknown config '%s'. Available: %s\n" "$wanted" "${names[*]}" >&2
      exit 2
    fi
  done
elif ! $install_all && [ -t 0 ] && [ -t 1 ]; then
  cursor=0
  cleanup() { printf '\033[?25h'; }
  trap cleanup EXIT INT TERM
  printf '\033[?25l'
  while :; do
    printf '\033[H\033[2J'
    printf 'Choose configs to install\n\n'
    printf '  Use ↑/↓ to move, Space to toggle, Enter to install.\n\n'
    for ((i = 0; i < ${#names[@]}; i++)); do
      [ "${selected[$i]}" -eq 1 ] && mark=x || mark=' '
      if [ "$i" -eq "$cursor" ]; then
        printf '\033[7m> [%s] %-12s %s\033[0m\n' "$mark" "${names[$i]}" "${descriptions[$i]}"
      else
        printf '  [%s] %-12s %s\n' "$mark" "${names[$i]}" "${descriptions[$i]}"
      fi
    done

    IFS= read -r -s -n 1 key || exit 130
    case "$key" in
      '') break ;;
      ' ')
        if [ "${selected[$cursor]}" -eq 1 ]; then selected[$cursor]=0; else selected[$cursor]=1; fi
        ;;
      k) [ "$cursor" -gt 0 ] && cursor=$((cursor - 1)) ;;
      j) [ "$cursor" -lt $((${#names[@]} - 1)) ] && cursor=$((cursor + 1)) ;;
      $'\033')
        IFS= read -r -s -n 2 -t 1 rest || rest=""
        case "$rest" in
          '[A') [ "$cursor" -gt 0 ] && cursor=$((cursor - 1)) ;;
          '[B') [ "$cursor" -lt $((${#names[@]} - 1)) ] && cursor=$((cursor + 1)) ;;
        esac
        ;;
    esac
  done
  cleanup
  trap - EXIT INT TERM
  printf '\033[H\033[2J'
fi

chosen=0
failed=0
for ((i = 0; i < ${#scripts[@]}; i++)); do
  [ "${selected[$i]}" -eq 1 ] || continue
  chosen=$((chosen + 1))
  printf '\n'
  log "Installing ${names[$i]}"
  if $config_only; then
    bash "${scripts[$i]}" --config-only
  else
    bash "${scripts[$i]}"
  fi
  if [ "$?" -ne 0 ]; then
    log "${names[$i]} installer failed"
    failed=$((failed + 1))
  fi
done

if [ "$chosen" -eq 0 ]; then
  log "Nothing selected."
elif [ "$failed" -gt 0 ]; then
  log "Finished with $failed failed installer(s)."
  exit 1
else
  log "Done."
fi
