#!/usr/bin/env bash
# roadmap-items.sh — report a roadmap's items for the Workflow driver.
#
# Usage: bash roadmap-items.sh <roadmap-slug-or-path>
#
# Prints one TAB-separated line per UNCHECKED item, then one DONE line:
#
#   <N>\t<deps>\t<size>\t<title>       deps: "" or "1,2"; size: S|M|L (default M)
#   DONE\t<n,n,…>                       the already-marked numbers ("" if none)
#
# `roadmap-to-workflow` Step 1 turns those lines into the driver's `items` and
# `done` args verbatim, and its Output counts the lines again after the run for
# the unchecked total. Nothing here sorts or filters: the driver's own
# computeWaves() decides the order and the scope.
#
# Exit codes: 0 printed, 1 no such roadmap (or one that could not be read),
# 2 usage.
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

# Byte-wise: in a UTF-8 locale macOS awk aborts on a byte it cannot decode,
# which truncated the item list mid-file. Every pattern is ASCII and the `—`
# token is an exact string compare, so bytes lose nothing. A pass that still
# fails (an unreadable file) is exit 1 too: its partial list must never run.
LC_ALL=C awk '
  function flush() { if (pend) { print n "\t" deps "\t" (size==""?"M":size) "\t" title; pend=0 } }
  # An item is a `### N. <title>` heading plus its status line, the first
  # non-blank line under it. The heading arms the pass; the status line decides
  # whether the item is captured or only counted as met. A heading with no
  # status line is neither: validate.sh names it, and it never runs.
  wait && /^[[:space:]]*$/ { next }
  wait {
    wait=0
    if ($0 ~ /^- \[ \]([[:space:]]|$)/) { size=""; deps=""; pend=1; next }   # unchecked — capture
    if ($0 ~ /^- \[[x~>-]\]([[:space:]]|$)/) {                                # marked — the driver
      donelist = (donelist=="" ? n : donelist "," n)                          # needs these to know
      next                                                                    # which deps are met
    }
  }
  /^### [0-9]+\. / {
    flush()
    n=$0;     sub(/^### /,"",n); sub(/\..*/,"",n)
    title=$0; sub(/^### [0-9]+\. /,"",title)
    wait=1
    next
  }
  # A heading that ATTEMPTED to be an item and drifted (a checkbox left in the
  # heading, a bullet before the number) closes the current item.
  # Otherwise its Dependencies/Size are attributed to the item ABOVE it — a
  # phantom dependency, a wrong wave, or the wrong size, with no signal.
  # Matched the same way `validate.sh` reports it, so both parsers agree on what
  # counts as an item attempt.
  /^#+[[:space:]]*[-*+]?[[:space:]]*\[[^]]?\]/ { flush(); next }
  /^#+[[:space:]]*[-*+][[:space:]]*[0-9]/       { flush(); next }
  # The section terminators the validate.sh block parser uses. Deliberately NOT
  # every `#`-prefixed line: a `#### Notes` sub-heading, or a `#` comment inside
  # a fenced block, sits INSIDE an item — flushing on those would drop that
  # an item Dependencies/Size on a file that validates perfectly clean.
  /^### / { flush(); next }
  /^## /  { flush(); next }
  /^---[[:space:]]*$/ { flush(); next }
  /^\*\*Dependencies:\*\*/ && pend { deps=$0; sub(/^\*\*Dependencies:\*\* */,"",deps); gsub(/[ \t]/,"",deps); if (deps=="—"||deps=="-"||tolower(deps)=="none"||tolower(deps)=="n/a") deps="" }
  # Size is upper-cased so a hand-typed `s` counts; anything else is the default.
  # A stale `**Model:**` line from an older roadmap matches no rule: it is an
  # ordinary body line and the item runs at the default size.
  /^\*\*Size:\*\*/        && pend { size=$0; sub(/^\*\*Size:\*\* */,"",size); gsub(/[ \t]/,"",size); size=toupper(size); if (size!="S" && size!="M" && size!="L") size="" }
  END { flush(); print "DONE\t" donelist }
' "$ROADMAP" || { echo "ERROR cannot read roadmap: $ROADMAP" >&2; exit 1; }
