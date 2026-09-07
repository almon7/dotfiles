#!/usr/bin/env bash
# Check or refresh vendored skills from one consistent upstream snapshot.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE=https://github.com/EveryInc/compound-engineering-plugin.git
PATHS=(skills/ce-simplify-code skills/ce-code-review)
export GIT_TERMINAL_PROMPT=0

fail() {
  printf '[agents] Skill update failed: %s\n' "$1" >&2
  exit 2
}

require_clean_skills() {
  local path changes
  for path in "$@"; do
    git -C "$DIR" ls-files --error-unmatch -- "$path/SKILL.md" > /dev/null \
      || fail "$path must be tracked in Git before refreshing"
  done
  changes=$(git -C "$DIR" status --porcelain --untracked-files=all --ignored -- "$@") \
    || fail 'could not check local skill changes'
  [[ -z "$changes" ]] || fail 'skill folders contain local changes or untracked files; commit or move them before refreshing'
}

refresh=false
(( $# <= 1 )) || fail 'expected no arguments, --refresh, or --help'
case "${1:-}" in
  -h|--help)
    printf 'Usage: bash %s [--refresh]\nChecks the two EveryInc skills; --refresh replaces clean copies with upstream.\n' "$0"
    exit 0 ;;
  '') ;;
  --refresh) refresh=true ;;
  *) fail "unexpected argument: $1" ;;
esac

if "$refresh"; then
  command -v rsync > /dev/null || fail 'refresh requires rsync'
  require_clean_skills "${PATHS[@]}"
fi

scratch=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-skill-check.XXXXXX")
trap 'rm -rf -- "$scratch"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Download only the selected folders; never run anything from upstream.
git -c http.lowSpeedLimit=1 -c http.lowSpeedTime=60 \
  clone --quiet --depth 1 --filter=blob:none --sparse --branch main \
  "$SOURCE" "$scratch/upstream" || fail 'could not fetch upstream'
git -c http.lowSpeedLimit=1 -c http.lowSpeedTime=60 \
  -C "$scratch/upstream" sparse-checkout set "${PATHS[@]}" \
  || fail 'could not download skill files'
revision=$(git -C "$scratch/upstream" rev-parse --short HEAD)
printf '[agents] Checking EveryInc skills against main at %s\n' "$revision"

# Validate both folders before a refresh can replace either one.
for path in "${PATHS[@]}"; do
  [[ -f "$DIR/$path/SKILL.md" && -f "$scratch/upstream/$path/SKILL.md" ]] \
    || fail "$path: missing local or upstream skill; check its source path"
done

if "$refresh"; then
  require_clean_skills "${PATHS[@]}"
fi

for path in "${PATHS[@]}"; do
  skill=${path##*/}
  result=0
  diff -qr "$DIR/$path" "$scratch/upstream/$path" > /dev/null || result=$?
  case "$result" in
    0) printf '[agents] %s: up to date\n' "$skill" ;;
    1)
      if "$refresh"; then
        require_clean_skills "$path"
        rsync -a --checksum --delete "$scratch/upstream/$path/" "$DIR/$path/" \
          || fail "$skill: refresh incomplete; inspect the Git diff before retrying"
        diff -qr "$DIR/$path" "$scratch/upstream/$path" > /dev/null \
          || fail "$skill: verification failed; inspect the Git diff before retrying"
        printf '[agents] %s: refreshed; review and commit the Git diff\n' "$skill"
      else
        printf '[agents] %s: differs from upstream (update available or local edits).\n' "$skill"
      fi
      printf '  https://github.com/EveryInc/compound-engineering-plugin/tree/%s/skills/%s\n' "$revision" "$skill"
      ;;
    *) fail "$skill: comparison failed" ;;
  esac
done
