#!/usr/bin/env bash
# Check or refresh vendored skills from one snapshot per upstream repository.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Repository | upstream directory | local skill name. New upstream skills are not added automatically.
SKILLS=(
  'EveryInc/compound-engineering-plugin|skills/ce-simplify-code|ce-simplify-code'
  'EveryInc/compound-engineering-plugin|skills/ce-code-review|ce-code-review'
  'mattpocock/skills|skills/engineering/ask-matt|ask-matt'
  'mattpocock/skills|skills/engineering/diagnosing-bugs|diagnosing-bugs'
  'mattpocock/skills|skills/engineering/grill-with-docs|grill-with-docs'
  'mattpocock/skills|skills/engineering/triage|triage'
  'mattpocock/skills|skills/engineering/improve-codebase-architecture|improve-codebase-architecture'
  'mattpocock/skills|skills/engineering/setup-matt-pocock-skills|setup-matt-pocock-skills'
  'mattpocock/skills|skills/engineering/tdd|tdd'
  'mattpocock/skills|skills/engineering/to-spec|to-spec'
  'mattpocock/skills|skills/engineering/to-tickets|to-tickets'
  'mattpocock/skills|skills/engineering/wayfinder|wayfinder'
  'mattpocock/skills|skills/engineering/implement|implement'
  'mattpocock/skills|skills/engineering/implement-spec|implement-spec'
  'mattpocock/skills|skills/engineering/prototype|prototype'
  'mattpocock/skills|skills/engineering/research|research'
  'mattpocock/skills|skills/engineering/domain-modeling|domain-modeling'
  'mattpocock/skills|skills/engineering/codebase-design|codebase-design'
  'mattpocock/skills|skills/engineering/code-review|code-review'
  'mattpocock/skills|skills/engineering/pr|pr'
  'mattpocock/skills|skills/engineering/retro|retro'
  'mattpocock/skills|skills/engineering/wizard|wizard'
  'mattpocock/skills|skills/productivity/grill-me|grill-me'
  'mattpocock/skills|skills/productivity/grilling|grilling'
  'mattpocock/skills|skills/productivity/handoff|handoff'
  'mattpocock/skills|skills/productivity/teach|teach'
  'mattpocock/skills|skills/productivity/to-questionnaire|to-questionnaire'
  'mattpocock/skills|skills/productivity/wait-what|wait-what'
  'mattpocock/skills|skills/productivity/writing-for-agents|writing-for-agents'
)
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
    printf 'Usage: bash %s [--refresh]\nChecks the vendored EveryInc and Matt Pocock skills; --refresh replaces clean copies with upstream.\n' "$0"
    exit 0 ;;
  '') ;;
  --refresh) refresh=true ;;
  *) fail "unexpected argument: $1" ;;
esac

PATHS=()
for mapping in "${SKILLS[@]}"; do
  IFS='|' read -r repository upstream_path skill <<< "$mapping"
  PATHS+=("skills/$skill")
done

if "$refresh"; then
  command -v rsync > /dev/null || fail 'refresh requires rsync'
  require_clean_skills "${PATHS[@]}"
fi

scratch=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-skill-check.XXXXXX")
trap 'rm -rf -- "$scratch"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Fetch every repository before any local skill can be replaced. Never run downloaded code.
for mapping in "${SKILLS[@]}"; do
  IFS='|' read -r repository upstream_path skill <<< "$mapping"
  upstream="$scratch/$repository"
  [[ -d "$upstream" ]] && continue
  source_paths=()
  for candidate in "${SKILLS[@]}"; do
    IFS='|' read -r source_repository source_path source_skill <<< "$candidate"
    if [[ "$source_repository" == "$repository" ]]; then
      source_paths+=("$source_path")
    fi
  done
  mkdir -p "${upstream%/*}"
  git -c http.lowSpeedLimit=1 -c http.lowSpeedTime=60 \
    clone --quiet --depth 1 --filter=blob:none --sparse --branch main \
    "https://github.com/$repository.git" "$upstream" || fail "$repository: could not fetch upstream"
  git -c http.lowSpeedLimit=1 -c http.lowSpeedTime=60 \
    -C "$upstream" sparse-checkout set "${source_paths[@]}" \
    || fail "$repository: could not download skill files"
  revision=$(git -C "$upstream" rev-parse --short HEAD)
  printf '%s\n' "$revision" > "$upstream.revision"
  printf '[agents] Checking %s skills against main at %s\n' "$repository" "$revision"
done

# Validate all mapped folders, including later repositories, before refreshing any skill.
for mapping in "${SKILLS[@]}"; do
  IFS='|' read -r repository upstream_path skill <<< "$mapping"
  [[ -f "$DIR/skills/$skill/SKILL.md" && -f "$scratch/$repository/$upstream_path/SKILL.md" ]] \
    || fail "$skill: missing local or upstream skill; check its source path"
done

if "$refresh"; then
  require_clean_skills "${PATHS[@]}"
fi

for mapping in "${SKILLS[@]}"; do
  IFS='|' read -r repository upstream_path skill <<< "$mapping"
  path="skills/$skill"
  upstream="$scratch/$repository/$upstream_path"
  revision=$(< "$scratch/$repository.revision")
  result=0
  diff -qr "$DIR/$path" "$upstream" > /dev/null || result=$?
  case "$result" in
    0) printf '[agents] %s: up to date\n' "$skill" ;;
    1)
      if "$refresh"; then
        require_clean_skills "$path"
        rsync -a --checksum --delete "$upstream/" "$DIR/$path/" \
          || fail "$skill: refresh incomplete; inspect the Git diff before retrying"
        diff -qr "$DIR/$path" "$upstream" > /dev/null \
          || fail "$skill: verification failed; inspect the Git diff before retrying"
        printf '[agents] %s: refreshed; review and commit the Git diff\n' "$skill"
      else
        printf '[agents] %s: differs from upstream (update available or local edits).\n' "$skill"
      fi
      printf '  https://github.com/%s/tree/%s/%s\n' "$repository" "$revision" "$upstream_path"
      ;;
    *) fail "$skill: comparison failed" ;;
  esac
done
