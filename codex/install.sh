#!/usr/bin/env bash
# Check Codex's own settings against the ones this repository tracks. Codex is
# installed elsewhere; this only reads ~/.codex/config.toml and, where a setting
# is missing from it, adds that one line.
set -euo pipefail    # abort on an error, an unset variable, or a failing pipeline stage

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"    # absolute path of this script's directory
LABEL=codex    # the tag log() puts in front of every message
source "$DIR/../install-lib.sh"    # pull in log, has, require_no_args, ...
require_no_args "$@"    # reject anything but an empty argument list or --help

DESIRED="$DIR/config.toml"    # the settings this repository tracks
ACTUAL="$HOME/.codex/config.toml"    # the file Codex actually reads

if [ ! -f "$ACTUAL" ]; then    # a machine where Codex has never written its config
  log "Creating $ACTUAL"
  mkdir -p "$(dirname "$ACTUAL")"
  : > "$ACTUAL"    # an empty file, so the one path below fills it in
fi

log "Checking $ACTUAL against $DESIRED"
TEMP="$ACTUAL.dotfiles-tmp.$$"    # $$ keeps concurrent runs off each other's file

# Read both files in one pass: the tracked settings first, then the live config,
# which is printed back out with any missing key inserted into the table it
# belongs to. A key written after a table header would join that table, so each
# one goes in before the header that ends its own - a top-level key before the
# first header in the file - and a table that is not there at all is appended.
# Only bare keys are recognised, which is all either file uses, and values are
# compared as text, so different quoting or a trailing comment reads as a
# difference: reported, never rewritten. The report goes to standard error
# because the rewritten file is what standard output carries.
awk -v label="$LABEL" '
  function trim(s) { sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s); return s }
  function table_of(s) { sub(/^[[:space:]]*\[[[:space:]]*/, "", s); sub(/[[:space:]]*\][[:space:]]*$/, "", s); return s }
  function is_setting() {    # on a "key = value" line, set K and V and return true
    if (!match($0, /^[[:space:]]*[A-Za-z0-9_-]+[[:space:]]*=/)) return 0    # RLENGTH spans the key and its "="
    K = trim(substr($0, 1, RLENGTH - 1)); V = trim(substr($0, RLENGTH + 1)); return 1
  }
  function fill(t,   i) {    # write out the settings table t turned out to be missing
    for (i = 1; i <= n; i++) if (table[i] == t && !found[i]) { print key[i] " = " value[i]; added[i] = seen = 1 }
  }
  function flush(   i) {    # a comment or a blank line introduces whatever follows it,
    for (i = 1; i <= held; i++) print pending[i]    # so it is held back and printed after
    held = 0    # an insertion rather than before it
  }

  NR == FNR {    # the tracked settings, recorded in the order they are written
    if ($0 ~ /^[[:space:]]*(#|$)/) next
    if ($0 ~ /^[[:space:]]*\[/) { want = table_of($0); next }
    if (!is_setting()) next
    n++; table[n] = want; key[n] = K; value[n] = V; at[want, K] = n
    next
  }

  { seen++ }    # how much has been written: FNR cannot tell an empty file from an unread one
  /^[[:space:]]*(#|$)/ { pending[++held] = $0; next }
  /^[[:space:]]*\[/ {    # this header ends the table above it: the last chance to insert
    fill(here); flush()
    here = table_of($0); opened[here] = 1
    print; next
  }
  { if (is_setting() && ((here, K) in at)) { found[at[here, K]] = 1; holds[at[here, K]] = V }
    flush(); print }

  END {
    fill(here); flush()    # the table the file ends inside, then its trailing lines
    for (i = 1; i <= n; i++) {    # whatever is left belongs to a table the file lacks
      if (found[i] || added[i]) continue
      if (!(table[i] in opened)) { if (seen) print ""; print "[" table[i] "]"; opened[table[i]] = 1; seen = 1 }
      print key[i] " = " value[i]; added[i] = 1
    }
    for (i = 1; i <= n; i++) {    # one line of report per tracked setting
      name = (table[i] == "" ? key[i] : table[i] "." key[i])
      if (added[i]) report = "Added " name " = " value[i]
      else if (holds[i] == value[i]) report = name " is already set to " value[i]
      # The file Codex reads wins: a deliberate local change is not ours to undo.
      else report = name " is " holds[i] " here, and " value[i] " in config.toml; leaving it alone"
      print "[" label "] " report > "/dev/stderr"
    }
  }
' "$DESIRED" "$ACTUAL" > "$TEMP"

cmp -s "$TEMP" "$ACTUAL" || cat "$TEMP" > "$ACTUAL"    # copy back, and only when something changed,
rm -f "$TEMP"    # so the file keeps its permissions and an unchanged run leaves no trace

# Nothing above installs Codex, and the settings are worth checking before it
# arrives as much as after, so this is a note rather than a failure.
has codex || log 'Codex itself is not installed here; its config is checked either way.'
