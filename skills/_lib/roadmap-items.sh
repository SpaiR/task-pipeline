#!/usr/bin/env bash
# roadmap-items.sh — report a roadmap's items for the Workflow driver.
#
# Usage: bash roadmap-items.sh <roadmap-slug-or-path>
#
# Prints one TAB-separated line per UNCHECKED item, then one DONE line:
#
#   <N>\t<deps>\t<model>\t<title>      deps: "" or "1,2"; model: haiku|sonnet|opus
#   DONE\t<n,n,…>                       the already-marked numbers ("" if none)
#
# `roadmap-to-workflow` Step 1 turns those lines into the driver's `items` and
# `done` args verbatim; `to-architecture` Step 2 reads the same lines beside its
# full roadmap read. Nothing here sorts or filters: the driver's own
# computeWaves() decides the order and the scope.
#
# Exit codes: 0 printed, 1 no such roadmap, 2 usage.
set -u

SRC="${BASH_SOURCE[0]}"
while [ -L "$SRC" ]; do D=$(cd "$(dirname "$SRC")" && pwd); SRC=$(readlink "$SRC"); [[ "$SRC" != /* ]] && SRC="$D/$SRC"; done
SCRIPT_DIR=$(cd "$(dirname "$SRC")" && pwd)

arg="${1:-}"
[[ -n "$arg" ]] || { echo "ERROR usage: roadmap-items.sh <roadmap-slug-or-path>" >&2; exit 2; }

# shellcheck source=./resolve-ws.sh
source "$SCRIPT_DIR/resolve-ws.sh"     # exports AI_DIR
# shellcheck source=./roadmap.sh
source "$SCRIPT_DIR/roadmap.sh"        # resolve_artifact_path

ROADMAP=$(resolve_artifact_path roadmap "$arg")
# Never let an unresolved path reach awk: `awk 'prog' ""` skips the empty
# filename and reads STDIN instead, which comes back as zero items and reads
# exactly like a fully-completed roadmap.
[[ -n "$ROADMAP" && -f "$ROADMAP" ]] || { echo "ERROR roadmap not found: $arg" >&2; exit 1; }

awk '
  function flush() { if (pend) { print n "\t" deps "\t" (model==""?"sonnet":model) "\t" title; pend=0 } }
  /^### - \[[ x~>-]\] [0-9]+\. / {
    flush()
    if ($0 ~ /^### - \[ \] /) {                     # unchecked item — start capturing
      n=$0;     sub(/^### - \[ \] /,"",n); sub(/\..*/,"",n)
      title=$0; sub(/^### - \[ \] [0-9]+\. /,"",title)
      model=""; deps=""; pend=1
    } else {                                        # already marked — the driver
      m=$0; sub(/^### - \[[x~>-]\] /,"",m); sub(/\..*/,"",m)   # needs these to know
      donelist = (donelist=="" ? m : donelist "," m)             # which deps are met
    }
    next
  }
  # `### Spec references → …` is a top-level heading that lives INSIDE an item
  # (the same tolerance validate.sh grants it), so it is NOT a terminator — it
  # may sit above **Dependencies:**, and flushing here would drop them.
  /^### Spec references/ { next }
  # A heading that ATTEMPTED to be an item and drifted (`[X]`, a double space
  # after the checkbox, `####`, a missing `- `) closes the current item.
  # Otherwise its Dependencies/Model are attributed to the item ABOVE it — a
  # phantom dependency, a wrong wave, or the wrong model, with no signal.
  # Matched the same way `validate.sh` reports it, so both parsers agree on what
  # counts as an item attempt.
  /^#+[[:space:]]*[-*+]?[[:space:]]*\[[^]]?\]/ { flush(); next }
  /^#+[[:space:]]*[-*+][[:space:]]*[0-9]/       { flush(); next }
  # The section terminators the validate.sh block parser uses. Deliberately NOT
  # every `#`-prefixed line: a `#### Notes` sub-heading, or a `#` comment inside
  # a fenced block, sits INSIDE an item — flushing on those would drop that
  # an item Dependencies/Model on a file that validates perfectly clean.
  /^### / { flush(); next }
  /^## /  { flush(); next }
  /^---[[:space:]]*$/ { flush(); next }
  /^\*\*Dependencies:\*\*/ && pend { deps=$0; sub(/^\*\*Dependencies:\*\* */,"",deps); gsub(/[ \t]/,"",deps); if (deps=="—"||deps=="-"||tolower(deps)=="none"||tolower(deps)=="n/a") deps="" }
  /^\*\*Model:\*\*/       && pend { model=$0; sub(/^\*\*Model:\*\* */,"",model); gsub(/[ \t]/,"",model); if (model!="haiku" && model!="sonnet" && model!="opus") model="" }
  END { flush(); print "DONE\t" donelist }
' "$ROADMAP"
