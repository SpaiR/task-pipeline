#!/usr/bin/env bash
# roadmap-items.sh — report a roadmap's items for the Workflow driver.
#
# Usage: bash roadmap-items.sh <roadmap-slug-or-path>
#
# Prints one TAB-separated line per UNCHECKED item, then one DONE line:
#
#   <N>\t<deps>\t<model>\t<title>\t<planned>
#                                       deps: "" or "1,2"; model: haiku|sonnet|opus
#   DONE\t<n,n,…>                       the already-marked numbers ("" if none)
#
# <planned> is the slug of a task file already written for that item — headers
# `Roadmap:` naming this roadmap and `Source item: #N` — or "" when there is
# none; the most recently modified one wins when several match. It is a hint for
# the skill's resume question, never part of the item list: a task file that
# cannot be read is skipped, not an error.
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

# The planned-file pass: every readable task file, newest first, headers only
# (the lines above the first `---`). The label of a `Roadmap:` link is the
# identity, as everywhere else; a bare slug counts the same. Only kebab-case
# basenames are reported — a slug is a filename, and the pairs below travel
# through `awk -v`, which would rewrite a backslash. A failed pass loses only
# the hint, never the item list.
RSLUG=$(basename "$ROADMAP" .md)
plans=""
tasks=()
ntasks=0
# Every `2>/dev/null` here sits outside the `$(…)`: under bash 5.3.20 on macOS
# a redirect inside the substitution segfaulted its child about once in twenty
# runs, and the hint vanished at random.
{ newest=$(ls -t "$AI_DIR"/task/*.md); } 2>/dev/null
while IFS= read -r f; do
  [[ -n "$f" && -f "$f" && -r "$f" ]] || continue
  tasks[ntasks]="$f"
  ntasks=$((ntasks + 1))
done <<EOF
$newest
EOF
if [[ "$ntasks" -gt 0 ]]; then
  { plans=$(LC_ALL=C awk -v rs="$RSLUG" '
    FNR == 1 { hdr=1; r=""; s="" }
    !hdr { next }
    /^---[[:space:]]*$/ {
      hdr=0
      f=FILENAME; sub(/.*\//,"",f); sub(/\.md$/,"",f)
      if (r==rs && s!="" && !(s in got) && f ~ /^[a-z0-9][a-z0-9-]*$/) { got[s]=1; out=out (out==""?"":" ") s ":" f }
      next
    }
    /^Roadmap:[[:space:]]/ {
      r=$0; sub(/^Roadmap:[[:space:]]*/,"",r); sub(/[[:space:]]+$/,"",r)
      if (r ~ /^\[[^]]*\]/) { sub(/^\[/,"",r); sub(/\].*/,"",r) }
    }
    /^Source item:[[:space:]]/ {
      s=$0; sub(/^Source item:[[:space:]]*/,"",s); sub(/[[:space:]]+$/,"",s)
      if (s ~ /^#[0-9]+$/) s=substr(s,2)+0; else s=""
    }
    END { print out }
  ' "${tasks[@]}"); } 2>/dev/null || plans=""
fi

# Byte-wise: in a UTF-8 locale macOS awk aborts on a byte it cannot decode,
# which truncated the item list mid-file. Every pattern is ASCII and the `—`
# token is an exact string compare, so bytes lose nothing. A pass that still
# fails (an unreadable file) is exit 1 too: its partial list must never run.
LC_ALL=C awk -v plans="$plans" '
  BEGIN { k=split(plans, pr, " "); for (j=1; j<=k; j++) { c=index(pr[j], ":"); plan[substr(pr[j],1,c-1)]=substr(pr[j],c+1) } }
  function flush() { if (pend) { print n "\t" deps "\t" (model==""?"sonnet":model) "\t" title "\t" ((n+0) in plan ? plan[n+0] : ""); pend=0 } }
  # An item is a `### N. <title>` heading plus its status line, the first
  # non-blank line under it. The heading arms the pass; the status line decides
  # whether the item is captured or only counted as met. A heading with no
  # status line is neither: validate.sh names it, and it never runs.
  wait && /^[[:space:]]*$/ { next }
  wait {
    wait=0
    if ($0 ~ /^- \[ \]([[:space:]]|$)/) { model=""; deps=""; pend=1; next }   # unchecked — capture
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
' "$ROADMAP" || { echo "ERROR cannot read roadmap: $ROADMAP" >&2; exit 1; }
