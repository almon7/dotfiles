#!/usr/bin/env bash
# Give every coding agent the same personal instructions and the same skills.
set -euo pipefail    # abort on an error, an unset variable, or a failing pipeline stage

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"    # absolute path of this script's directory
LABEL=agents    # the tag log() puts in front of every message
source "$DIR/../install-lib.sh"    # pull in log, has, link_config, ...

FILE="$DIR/AGENTS.md"    # the single tracked instructions file both agents will read
SKILLS="$DIR/skills"    # the single tracked skills folder both agents will read

usage() {
  printf 'Usage: %s\n' "$0"    # how the script is invoked
  printf 'Links AGENTS.md and skills/ to the paths Claude Code and Codex read.\n'    # what it does
}

case "${1:-}" in    # this installer takes no options
  -h|--help) usage; exit 0 ;;    # print the usage text and stop
  '') ;;    # no argument: the normal case
  *) printf 'Unexpected argument: %s\n' "$1" >&2; exit 2 ;;    # anything else is a mistake
esac

# The two agents hard-code where they look, and neither reads a plain
# ~/AGENTS.md; link_config creates the directory when the tool is not installed
# here yet, so the file is in place the moment it is.
link_config "$FILE" "$HOME/.claude/CLAUDE.md"    # where Claude Code reads it
link_config "$FILE" "$HOME/.codex/AGENTS.md"    # where Codex reads it

# Skills are hard-coded the same way, so both names point at the one tracked
# folder instead of drifting into two copies. Nothing in it is specific to
# either agent, which is why it sits here beside the shared instructions file.
link_config "$SKILLS" "$HOME/.agents/skills"    # where Codex reads skills
link_config "$SKILLS" "$HOME/.claude/skills"    # where Claude Code reads skills

# find-docs calls the `ctx7` command. The skill links either way, but without the
# CLI every documentation lookup it makes fails at the shell, so say so here
# rather than leaving the agent to discover it mid-question.
has ctx7 || log 'ctx7 is missing, so the find-docs skill cannot run. Install the context7 component.'    # warn, do not fail
