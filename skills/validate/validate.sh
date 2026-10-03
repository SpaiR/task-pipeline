#!/usr/bin/env bash
# validate.sh — Validate the format of task-pipeline artifacts.
#
# Usage: see the `--help` heredoc at the bottom of this file — the one copy
# users actually see, and the only place the subcommand list is maintained.
#
# The layout is flat: <slug> is both the filename and the identity — there is no
# task-id, no workspace, no active-task pointer. This is an OPTIONAL
# self-check; no hook calls it. A task/roadmap `Spec:` header whose slug doesn't
# resolve to a .task/spec/<slug>.md is reported as a WARN (dangling reference),
# never an ERROR — the only cross-file check, and advisory only. A header whose
# link target disagrees with its own label is a second WARN, checked within the
# one line. Both header forms are accepted: `Spec: [<slug>](../spec/<slug>.md)`
# (canonical) and the bare `Spec: <slug>` that earlier versions wrote.
#
# Exit codes:
#   0 — all checks passed
#   1 — at least one validation error
#   2 — usage error or missing precondition (.task/CLAUDE.md absent)
#
# Output: each issue is printed on its own line as
#     <severity> <artifact>: <message>
# where <severity> is ERROR (counted toward exit 1) or WARN (informational).
# A final summary line is always printed.

set -u
# Note: do NOT use `set -e` — we collect issues and report them all at once
# rather than aborting on the first failure.

# Byte-wise, for the whole script: every awk, grep and `[[ =~ ]]` below parses
# hand-edited text that may hold a byte the caller's locale cannot decode. In a
# UTF-8 locale macOS awk aborts on one ("towc: multibyte conversion failure"),
# and each section check is a negated awk, so an abort read as a missing
# section; the title's `=~` failed to match `.+` across it. Every pattern is
# ASCII, and the one non-ASCII comparison (the `—` no-dependency token) is an
# exact string match, so bytes lose nothing.
export LC_ALL=C

# AI_DIR is resolved once, when resolve-ws.sh is sourced below, by its
# `find_ai_dir` — an upward walk so validation works from any subdir, not only
# the project root. It is deliberately NOT hardcoded to `.task` here: pinning it
# would pre-empt the walk.
ERRORS=0
WARNS=0

err() { echo "ERROR $1: $2" >&2; ERRORS=$((ERRORS + 1)); }
warn() { echo "WARN $1: $2" >&2; WARNS=$((WARNS + 1)); }

# Locate this script's directory via the symlink-tolerant idiom used elsewhere
# in the pipeline, then source the shared helpers directly: `_lib/resolve-ws.sh`
# (exports AI_DIR) and `_lib/roadmap.sh` (artifact-path + progress helpers).
# validate.sh keeps its own issue-collection / exit semantics rather than the
# standard `set -euo pipefail` shape, so it sources these two on its own.
SRC="${BASH_SOURCE[0]}"
while [ -L "$SRC" ]; do D=$(cd "$(dirname "$SRC")" && pwd); SRC=$(readlink "$SRC"); [[ "$SRC" != /* ]] && SRC="$D/$SRC"; done
SCRIPT_DIR=$(cd "$(dirname "$SRC")" && pwd)
# shellcheck source=../_lib/resolve-ws.sh
source "$SCRIPT_DIR/../_lib/resolve-ws.sh"
# shellcheck source=../_lib/roadmap.sh
source "$SCRIPT_DIR/../_lib/roadmap.sh"

# --- Precondition: .task/CLAUDE.md ---
require_config() {
  if [[ ! -f "$AI_DIR/CLAUDE.md" ]]; then
    # Keep the literal substring `CLAUDE.md not found` — roadmap-to-workflow
    # Step 0 matches it in the VALIDATE: block, and so do the capture skills,
    # since write-task.sh exits 0 once the file is written and exit 2 never
    # reaches them.
    # Everything after it is for the human who ran this script by hand, which
    # is the only way to reach this line.
    echo "ERROR precondition: CLAUDE.md not found at $AI_DIR/CLAUDE.md" >&2
    echo "  The project isn't set up yet. Run /task:to-task, /task:to-roadmap or" >&2
    echo "  /task:to-spec once — those three write .task/CLAUDE.md" >&2
    echo "  inline on first use." >&2
    exit 2
  fi
}

# --- awk_report <awk-program> <file> ---
# Runs an awk check whose output is `ERROR <label>: …` / `WARN <label>: …` lines,
# echoes each to stderr and counts it by severity. Called via process
# substitution so the counting loop runs in THIS shell and can bump ERRORS /
# WARNS directly — the same reason `err`/`warn` are plain functions. `$label` is
# read from the caller's scope, as those two do.
#
# The awk runs byte-wise under the script-wide `LC_ALL=C` pin above.
awk_report() {
  local line
  while IFS= read -r line; do
    echo "$line" >&2
    [[ "$line" == ERROR* ]] && ERRORS=$((ERRORS + 1))
    [[ "$line" == WARN* ]] && WARNS=$((WARNS + 1))
  done < <(awk -v label="$label" "$1" "$2")
}

# Task and spec path resolution reuse `resolve_artifact_path <kind> <arg>` from
# `_lib/roadmap.sh` (sourced above) — same three-branch lookup as the roadmap
# resolver, keyed on the .task subdirectory.

# --- check_spec_refs <file> <label> ---
# WARN (never ERROR) for any `Spec:` header in <file> whose slug does not
# resolve to an existing .task/spec/<slug>.md. This is the only cross-file
# check in the pipeline, and it is advisory — validate.sh is not a gate.
# Runs in the caller's shell (not a subshell), so WARNS is updated directly.
#
# The header value is a Markdown link — `Spec: [<slug>](../spec/<slug>.md)` — so
# viewers can navigate it; the LINK LABEL carries the identity. The bare
# `Spec: <slug>` form predates that and stays accepted: artifacts written by
# earlier versions are still valid, and flagging them all as dangling would make
# this the noisiest check in the pipeline instead of its only useful one.
#
# Resolution is label-only: the canonical path is always $AI_DIR/spec/<slug>.md,
# and a relative href would resolve against the caller's cwd, not the artifact's
# directory. But the href is still READ, for one intra-line check — a target that
# disagrees with its label is a WARN of its own. Nothing else would ever catch it:
# the agent follows the label and works correctly, so a stale target after a
# rename silently sends every human who clicks it to the wrong file, which is the
# single failure the link form exists to prevent. This stays an intra-line
# consistency check, NOT a second cross-file one — the dangling-spec WARN below
# remains the pipeline's only cross-file validation.
#
# The awk split is deliberately forgiving, because these lines are hand-edited:
# backticks are stripped BEFORE the link is unwrapped (so `` `[s](t)` `` and
# `` [`s`](t) `` both reduce), trailing text after the link is tolerated (a
# literal copy of a template's `(one line per spec; …)` annotation is the common
# case), and the extracted label is re-trimmed. Anchoring the pattern at
# end-of-line instead would leave those forms un-unwrapped and emit a WARN naming
# a garbage slug on a spec that exists. The bare form gets the same tolerance
# from the `else` branch, which truncates at the first whitespace run — a slug
# never contains one, so the same copied annotation cannot corrupt it either.
#
# Only the HEADER BLOCK is scanned — the awk stops at the first `---` separator
# (task) or the first `## ` heading (roadmap), whichever comes first, because
# `Spec:` is defined as a header line and a body line that merely starts with
# `Spec: ` (a quoted example, a pasted template line) is not a reference.
#
# Runs in the caller's shell (not a subshell), so WARNS is updated directly.
check_spec_refs() {
  local file="$1" label="$2" slug target
  while IFS=$'\t' read -r slug target; do
    [[ -z "$slug" ]] && continue
    if [[ ! -f "$AI_DIR/spec/$slug.md" ]]; then
      warn "$label" "Spec: $slug — no such spec at $AI_DIR/spec/$slug.md (dangling reference)"
    fi
    # Its own check, not an `elif`: a header both dangling and mis-targeted
    # reports both, as the contract describes two independent WARNs.
    if [[ -n "$target" && "$target" != "../spec/$slug.md" ]]; then
      warn "$label" "Spec: $slug — link target '$target' does not match the slug (expected '../spec/$slug.md'); agents follow the label, so only a human clicking the link would land on the wrong file"
    fi
  done < <(awk '
    # `Spec:` is a HEADER line: above the `---` separator in a task, directly
    # under `# <Title>` (above the first `## ` heading) in a roadmap. Stop at
    # whichever bound comes first, so a `Spec:`-shaped line quoted in a body
    # (e.g. the attach-by-hand line from to-spec'\''s footer, pasted into a
    # Description) never emits a spurious dangling-reference WARN.
    /^---[[:space:]]*$/ { exit }
    /^## /              { exit }
    /^Spec:[[:space:]]/ {
      v = $0
      sub(/^Spec:[[:space:]]*/, "", v)
      gsub(/`/, "", v)
      target = ""
      if (match(v, /^\[[^]]+\]\([^)]*\)/)) {
        link = substr(v, RSTART, RLENGTH)
        slug = link;   sub(/^\[/, "", slug);      sub(/\].*$/, "", slug)
        target = link; sub(/^[^(]*\(/, "", target); sub(/\)$/, "", target)
        v = slug
      } else {
        # Bare `Spec: <slug>` — the legacy form. Give it the same trailing-text
        # tolerance the link branch above gets: a slug never contains
        # whitespace, so anything past the first space is a copied template
        # annotation or a hand-written comment, not part of the identity.
        # Without this, `Spec: event-envelope  (one line per relevant spec;
        # omit if none)` WARNs about a garbage slug on a spec that exists.
        sub(/[[:space:]].*$/, "", v)
      }
      sub(/^[[:space:]]+/, "", v);      sub(/[[:space:]]+$/, "", v)
      sub(/^[[:space:]]+/, "", target); sub(/[[:space:]]+$/, "", target)
      if (v != "") print v "\t" target
    }
  ' "$file" 2>/dev/null)
}

# ---------------- task.md ----------------
# One format for every task file — to-task's and the driver's plan agent's:
#   line 1   — `# <Title>` (plain title, no task-id)
#   `---`    — separator between header and body
#   `## Description` — always present
#   `## Plan`  — always present, with >=1 `### Step N:` block.
#   `## Tests` — OPTIONAL; if present, require >=1 `### Test N:` block.
validate_task() {
  local file="$1"
  local label="task($file)"

  local first_line
  first_line=$(head -1 "$file")
  if ! [[ "$first_line" =~ ^\#\ .+$ ]]; then
    err "$label" "first line must match '# <Title>'; got: ${first_line:-<empty>}"
  fi

  # The separator must sit in the HEADER block — before the first `## ` heading.
  # A `---` thematic break inside the body must not satisfy this check, or a
  # deleted header separator would pass silently.
  if ! awk '/^---[[:space:]]*$/{found=1; exit} /^## /{exit} END{exit !found}' "$file"; then
    err "$label" "missing '---' separator between header and Description (a '---' inside the body does not count)"
  fi

  if ! grep -qE '^## Description[[:space:]]*$' "$file"; then
    err "$label" "missing '## Description' section heading"
  fi

  # `## Plan` is required, with at least one `### Step N:` block: the executing
  # session implements it, and the reviewer takes its fix scope from its Touches.
  if ! grep -qE '^## Plan[[:space:]]*$' "$file"; then
    err "$label" "missing '## Plan' section heading"
  elif ! awk '/^## Plan[[:space:]]*$/{flag=1; next} /^## /{flag=0} flag && /^### Step [0-9]+:/{found=1} END{exit !found}' "$file"; then
    err "$label" "'## Plan' section is present but contains no '### Step N:' blocks"
  fi

  # `## Tests` is OPTIONAL. If present, it must carry at least one `### Test N:`.
  if ! awk '/^## Tests[[:space:]]*$/{seen=1; flag=1; next} /^## /{flag=0} flag && /^### Test [0-9]+:/{found=1} END{exit (seen && !found)}' "$file"; then
    err "$label" "'## Tests' section is present but contains no '### Test N:' blocks"
  fi

  # `## Execution` must be present — it is the pointer that sends the executing
  # session to `.task/CLAUDE.md` → `## Executing a task`, which carries implement
  # → commit → `task:code-reviewer` → auto-mark. The pointer is load-bearing even
  # though the platform also loads `.task/CLAUDE.md` on its own: that load only
  # fires for file-read tools, so a session that opens the artifact with `cat`
  # would otherwise get no instructions at all. Check presence, not wording.
  if ! grep -qE '^## Execution[[:space:]]*$' "$file"; then
    err "$label" "missing '## Execution' section heading — the executing session has no pointer to .task/CLAUDE.md without it"
  fi

  # Dangling `Spec:` header references → WARN (advisory, not an error).
  check_spec_refs "$file" "$label"
}

# ---------------- spec.md ----------------
# Standalone technical-decision spec (.task/spec/<slug>.md):
#   line 1     — `# <Title>` (a title; conventionally `# Spec: <Title>`)
#   >=1 `## N.` numbered decision section.
# No `---` separator: a spec carries no parser-stable headers above a body,
# so there is nothing to separate (unlike task.md).
validate_spec() {
  local file="$1"
  local label="spec($file)"

  local first_line
  first_line=$(head -1 "$file")
  if ! [[ "$first_line" =~ ^\#\ .+$ ]]; then
    err "$label" "first line must match '# <Title>'; got: ${first_line:-<empty>}"
  fi

  if ! grep -qE '^## [0-9]+\. .+$' "$file"; then
    err "$label" "no numbered decision sections matching '## N. <title>'"
  fi
}

# ---------------- roadmap file ----------------
# Resolution order is implemented in `_lib/roadmap.sh:resolve_artifact_path`.

validate_roadmap() {
  local raw="$1"
  local file
  file=$(resolve_artifact_path roadmap "$raw")
  if [[ -z "$file" ]]; then
    if [[ "$raw" == */* ]]; then
      err "roadmap($raw)" "file not found at $raw"
    else
      err "roadmap($raw)" "file not found (looked at $AI_DIR/roadmap/$raw(.md))"
    fi
    return
  fi
  local label
  label="roadmap($file)"

  # Dangling `Spec:` header references → WARN (advisory, not an error).
  check_spec_refs "$file" "$label"

  # CRLF. The parsers strip different whitespace classes — roadmap-items.sh
  # strips `[ \t]`, this file strips `[[:space:]]` — so a trailing CR survives
  # into the driver's `**Dependencies:**` / `**Model:**` values, where it becomes
  # a phantom dependency on a missing item and silently drops the model hint.
  # Flag the file once here instead of normalizing CR in every parser.
  if grep -q $'\r' "$file"; then
    err "$label" "file has CRLF line endings — the driver keeps the trailing CR in **Dependencies:** / **Model:** values, turning a dependency into a phantom one and dropping the model hint; convert the file to LF"
  fi

  # --- Item shape ------------------------------------------------------------
  # An item is a `### N. <title>` heading whose first non-blank line is its
  # status line, `- [ ] Done` with a state from the 5-state class `[ x~>-]`.
  #
  # Runs BEFORE the required-heading guard below, on purpose: when EVERY heading
  # has drifted, that guard returns early, and this is the only check that can
  # tell the operator WHY the file looks itemless.
  #
  # A heading that ATTEMPTED to be an item and missed the canonical anchor is not
  # an item to ANY consumer — `roadmap_progress_counts` under-counts it,
  # roadmap-items.sh (the driver's item source) skips it, and the block parser
  # opens no block for it, so its missing sub-headings go unreported too.
  # Unflagged, the file validates clean while an item silently vanishes and the
  # autopilot reports "all items shipped" having never run it. Three shapes
  # count as an attempt: a checkbox-ish bracket in the heading (`[ ]`, `[X]`,
  # `[]` — the body capped at ONE character so a heading that opens with a
  # Markdown link, `### [text](url)`, is not swept up), a bullet before the
  # number, and a `###` number that misses the `### N. <title>` spacing. A heading with no status line under it is the
  # same silent vanishing, so it is named too; inside `## Architecture` a
  # numbered heading is the block parser's to name, with its own message.
  # The reverse holds as well: a `- [ ] Done` line no item heading owns is an
  # item whose heading drifted out of the grammar entirely — `#### N.`, `## N.`,
  # a bold line — so the status line it left behind is named.
  awk_report '
    /^## / { in_arch = ($0 ~ /^## Architecture([[:space:]]|$)/) }
    wait && /^[[:space:]]*$/ { next }
    wait {
      wait = 0
      if ($0 ~ /^- \[[ x~>-]\]([[:space:]]|$)/) next
      print "ERROR " label ": Task " item " has no status line — the first line under its heading must be `- [ ] Done` (or [x], [~], [>], [-]); got: " $0
    }
    /^- \[[ x~>-]\] Done[[:space:]]*$/ {
      print "ERROR " label ": status line with no `### N. <title>` item heading directly above it — the item it belongs to is invisible to every parser: " $0
      next
    }
    /^### [0-9]+\. .+$/ {
      if (in_arch) next
      item = $0; sub(/^### /, "", item); sub(/\..*$/, "", item); wait = 1
      next
    }
    /^#+[[:space:]]*[-*+]?[[:space:]]*\[[^]]?\]/ {
      print "ERROR " label ": item heading carries a checkbox; the heading is `### N. <title>` and the checkbox goes on the `- [ ] Done` status line under it: " $0
      next
    }
    /^#+[[:space:]]*[-*+][[:space:]]*[0-9]/ {
      print "ERROR " label ": item heading carries a bullet; required form is `### N. <title>`: " $0
      next
    }
    /^###[[:space:]]*[0-9]+\./ {
      print "ERROR " label ": item heading does not match the required `### N. <title>` form: " $0
      next
    }
    END {
      if (wait)
        print "ERROR " label ": Task " item " has no status line — the first line under its heading must be `- [ ] Done` (or [x], [~], [>], [-]); got: end of file"
    }
  ' "$file"

  # Find item headings. The status line under each is what auto-mark flips and
  # what item selection reads; the pass above names any heading without one.
  if ! grep -qE '^### [0-9]+\. .+$' "$file"; then
    err "$label" "no item headings matching '### N. <title>' — every item is that heading plus a '- [ ] Done' status line (roadmap-to-workflow auto-mark and item selection rely on both)"
    return
  fi

  # Item numbers are the auto-mark key — task:code-reviewer's awk flip keys on
  # N and requires exactly one heading for it, so a duplicate N makes the
  # review FAIL and stops the wave outright. Flag any number that appears on more than
  # one item heading. Compare numerically — `1.` and `01.` are the same item to
  # every other consumer (the Dependencies check below, the driver's `0*` match).
  # A numbered heading inside `## Architecture` is the block parser's error, not
  # a second copy of the item.
  local dup
  dup=$(awk '
    /^## / { in_arch = ($0 ~ /^## Architecture([[:space:]]|$)/) }
    !in_arch && match($0, /^### [0-9]+\./) {
      s = substr($0, RSTART, RLENGTH); gsub(/[^0-9]/, "", s); cnt[s + 0]++
    }
    END { for (n in cnt) if (cnt[n] > 1) print n }
  ' "$file")
  if [[ -n "$dup" ]]; then
    while IFS= read -r d; do
      [[ -z "$d" ]] && continue
      err "$label" "duplicate item number $d — item numbers must be unique (roadmap-to-workflow auto-mark keys on the number)"
    done <<< "$dup"
  fi

  # Item numbers start at 1: the driver asserts `n >= 1` on every item it is
  # handed, so an item `0.` (or `00.`) that validated clean would still make the
  # launch fail with `bad args`. The Dependencies check below rejects a `0`
  # dependency for the same reason.
  awk_report '
    /^## / { in_arch = ($0 ~ /^## Architecture([[:space:]]|$)/) }
    !in_arch && match($0, /^### [0-9]+\./) {
      s = substr($0, RSTART, RLENGTH); gsub(/[^0-9]/, "", s)
      if (s + 0 == 0) print "ERROR " label ": item number " s " — item numbers start at 1 (the roadmap-to-workflow driver rejects 0): " $0
    }
  ' "$file"

  # --- `**Dependencies:**` values, checked against this same file -------------
  # Only UNCHECKED items are checked: the driver reads dependencies while
  # collecting runnable items, so a shipped `[x]` item's dependency is history
  # nothing consumes — erroring on it would make a completed roadmap unfixable
  # by format after an item is tidied away.
  # Item state is closed by the same terminators the collector uses, so a stray
  # `**Dependencies:**` under `## Out of scope` is not billed to the last item.
  # The status line settles `open`; an item without one is never open.
  awk_report '
    wait && /^[[:space:]]*$/ { next }
    wait { wait = 0; if ($0 ~ /^- \[ \]([[:space:]]|$)/) { open = 1; next } }
    !in_arch && /^### [0-9]+\. / {
      m = $0; sub(/^### /, "", m); sub(/\..*$/, "", m)
      item = m; open = 0; wait = 1; items[m + 0] = 1; next
    }
    /^#+[[:space:]]*[-*+]?[[:space:]]*\[[^]]?\]/ { item = ""; next }
    /^#+[[:space:]]*[-*+][[:space:]]*[0-9]/       { item = ""; next }
    /^### /             { item = ""; next }
    /^## /              { in_arch = ($0 ~ /^## Architecture([[:space:]]|$)/); item = ""; next }
    /^---[[:space:]]*$/ { item = ""; next }
    /^\*\*Dependencies:\*\*/ {
      if (item == "" || !open) next
      raw = $0; sub(/^\*\*Dependencies:\*\*[[:space:]]*/, "", raw)
      sub(/[[:space:]]+$/, "", raw)
      v = raw; gsub(/[[:space:]]/, "", v)
      lv = tolower(v)
      if (v == "" || v == "—" || v == "-" || lv == "none" || lv == "n/a") next
      # Test the RAW value first. Stripping whitespace before the format check
      # is what silently fuses the `1 2` hand edit into a dependency on item 12.
      if (raw ~ /[[:space:]]/ && raw !~ /^[0-9]+([[:space:]]*,[[:space:]]*[0-9]+)*$/) {
        print "ERROR " label ": Task " item " has a space-separated **Dependencies:** value \"" raw "\" — separate item numbers with commas (`1, 2`); without them the value reads as the single item " v
        next
      }
      if (v !~ /^[0-9]+(,[0-9]+)*$/) {
        print "ERROR " label ": Task " item " has an unparsable **Dependencies:** value \"" raw "\" — write an em dash for none, or a comma-separated list of item numbers"
        next
      }
      k = split(v, d, ",")
      for (i = 1; i <= k; i++) {
        if (d[i] + 0 == 0) {
          print "ERROR " label ": Task " item " depends on item " d[i] " — item numbers start at 1 (the roadmap-to-workflow driver rejects 0)"
          continue
        }
        if (d[i] + 0 == item + 0) {
          print "ERROR " label ": Task " item " lists itself in **Dependencies:** — the driver reads that as an unsatisfiable cycle and hard-stops the run"
          continue
        }
        nref++; ref_item[nref] = item; ref_num[nref] = d[i]
      }
      next
    }
    # Item numbers are compared NUMERICALLY, so a zero-padded `01.` heading and a
    # dependency written `1` are the same item, as every other consumer treats them.
    END {
      for (i = 1; i <= nref; i++)
        if (!((ref_num[i] + 0) in items))
          print "ERROR " label ": Task " ref_item[i] " depends on item " ref_num[i] ", which has no item heading in this file"
    }
  ' "$file"

  # The per-item block parser: requires the `**Ready description:**` label and
  # its quoted bold sub-headings. Reported through `awk_report`, like the
  # checks above it.
  awk_report '
    function flush_block() {
      if (in_block == 0) return
      if (!has_ready)    print "ERROR " label ": Task " task_no " missing '\''**Ready description:**'\'' label"
      if (!has_context)  print "ERROR " label ": Task " task_no " missing '\''> **Context**'\'' sub-heading"
      if (!has_goal)     print "ERROR " label ": Task " task_no " missing '\''> **Goal**'\'' sub-heading"
      if (!has_outcomes) print "ERROR " label ": Task " task_no " missing '\''> **Outcomes**'\'' sub-heading"
      if (!has_accept)   print "ERROR " label ": Task " task_no " missing '\''> **Acceptance criteria**'\'' sub-heading"
      in_block = 0
      has_ready = has_context = has_goal = has_outcomes = has_accept = 0
      task_no = ""
    }

    # Track `## Architecture` without consuming the line — the `## ` flush rule
    # below must still see it.
    /^## / { in_arch = ($0 ~ /^## Architecture([[:space:]]|$)/) }

    /^### [0-9]+\. / {
      flush_block()
      m = $0
      sub(/^### /, "", m)
      sub(/\..*$/, "", m)
      if (in_arch)
        print "ERROR " label ": numbered sub-heading in ## Architecture reads as item " m " — write a `- #" m " — …` bullet instead: " $0
      else {
        in_block = 1
        task_no = m
      }
      next
    }

    # A drifted item-heading ATTEMPT closes the block too, so this parser and
    # the driver'"'"'s Step 1 collector agree on what ends an item.
    /^#+[[:space:]]*[-*+]?[[:space:]]*\[[^]]?\]/ { flush_block(); next }
    /^#+[[:space:]]*[-*+][[:space:]]*[0-9]/       { flush_block(); next }

    # Stop at the next `### ` heading: sub-headings inside the blockquote are
    # bold lines (`> **Goal**`), never headings, so any top-level `### ` ends
    # the block.
    /^### / { flush_block(); next }
    /^## /  { flush_block(); next }
    /^---[[:space:]]*$/ { flush_block(); next }

    {
      if (in_block) {
        # The `**Ready description:**` label is required: `to-task` and the
        # plan agent of the driver (both via roadmap-item.md step 3) look for it to
        # find the item body, so an item that carries the sub-headings without
        # it is not pickable. flush_block() errors when this stays 0.
        if ($0 ~ /\*\*Ready description:\*\*/) has_ready = 1
        # Sub-headings MUST be inside the `**Ready description:**` blockquote
        # (`> **Goal**`, etc.) — to-task / the driver plan agent strip `> `
        # before parsing, so a bare `**Goal**` line outside the quote would not
        # be recognized as the description body. Require the `> ` prefix.
        if ($0 ~ /^>[[:space:]]+\*\*Context\*\*[[:space:]]*$/) has_context = 1
        if ($0 ~ /^>[[:space:]]+\*\*Goal\*\*[[:space:]]*$/) has_goal = 1
        if ($0 ~ /^>[[:space:]]+\*\*Outcomes\*\*[[:space:]]*$/) has_outcomes = 1
        # `**Invariants**` is an OPTIONAL sub-heading — not every item carries an
        # invariant, so it is deliberately not tracked or required here (the
        # other four are mandatory). See docs/contract.md § Roadmap file format.
        if ($0 ~ /^>[[:space:]]+\*\*Acceptance criteria\*\*[[:space:]]*$/) has_accept = 1
      }
    }

    END { flush_block() }
  ' "$file"

  # --- `## Architecture` (optional; written by to-roadmap) -------------------
  # WARN only, never ERROR: no parser consumes this section — planners read it as
  # the intended shape — and any roadmap ERROR stops roadmap-to-workflow from
  # launching, which a stale sketch must not do. Three checks:
  #   - more than one section: a planner reads one and silently misses the rest;
  #   - a required sub-heading missing (`### Item sketches` only while unchecked
  #     items remain — a finished roadmap has nothing left to sketch);
  #   - an `#N` item reference with no item heading, e.g. after a renumbering.
  # The section is any `## Architecture` heading, trailing text included
  # (`## Architecture — draft`), since a planner reads it all the same.
  # The `#N` scan is scoped to the section, drops code spans first (`#333`,
  # `C#`), and skips a match glued to a word, path or entity character (`.md#2-x`,
  # `page#2`, `&#39;`) or followed by a word character — so a link anchor never
  # reads as item 2, while `#2→#4` without spaces still counts both. POSIX awk
  # has no `\b`, hence the match() loop. Items may sit below the section, so
  # refs resolve at END.
  awk_report '
    wait && /^[[:space:]]*$/ { next }
    wait { wait = 0; if ($0 ~ /^- \[ \]([[:space:]]|$)/) { open++; next } }
    !in_arch && /^### [0-9]+\. / {
      m = $0; sub(/^### /, "", m); sub(/\..*$/, "", m)
      items[m + 0] = 1; wait = 1
      next
    }
    /^## / {
      in_arch = ($0 ~ /^## Architecture([[:space:]]|$)/)
      if (in_arch) narch++
      next
    }
    !in_arch { next }
    /^### Components[[:space:]]*$/    { has_comp = 1; next }
    /^### Item sketches[[:space:]]*$/ { has_sketch = 1; next }
    {
      line = $0
      gsub(/`[^`]*`/, "", line)
      s = line; off = 0
      while (match(s, /#[0-9]+/)) {
        p = off + RSTART
        prev = (p == 1) ? " " : substr(line, p - 1, 1)
        nxt = substr(line, p + RLENGTH, 1)
        if (prev !~ /[[:alnum:]_.&#\/-]/ && nxt !~ /[[:alnum:]_]/) {
          n = substr(line, p + 1, RLENGTH - 1) + 0
          if (!(n in seen)) { seen[n] = 1; nref++; ref_num[nref] = n }
        }
        off = p + RLENGTH - 1
        s = substr(line, off + 1)
      }
    }
    END {
      if (narch == 0) exit
      if (narch > 1)
        print "WARN " label ": " narch " `## Architecture` sections — planners read one; merge them into a single section"
      if (!has_comp)
        print "WARN " label ": `## Architecture` has no `### Components` sub-heading"
      if (!has_sketch && open > 0)
        print "WARN " label ": `## Architecture` has no `### Item sketches` sub-heading while unchecked items remain"
      for (i = 1; i <= nref; i++)
        if (!(ref_num[i] in items))
          print "WARN " label ": `## Architecture` cites #" ref_num[i] ", which has no item heading in this file"
    }
  ' "$file"
}

# ---------------- main ----------------
cmd="${1:-}"
shift || true
case "$cmd" in
  task)
    require_config
    if [[ -z "${1:-}" ]]; then
      echo "ERROR usage: 'validate.sh task <slug>' requires a slug argument." >&2
      exit 2
    fi
    task_path=$(resolve_artifact_path task "$1")
    if [[ -z "$task_path" ]]; then
      if [[ "$1" == */* ]]; then
        err "task($1)" "file not found at $1"
      else
        err "task($1)" "file not found (looked at $AI_DIR/task/$1(.md))"
      fi
    else
      validate_task "$task_path"
    fi
    ;;
  roadmap)
    require_config
    if [[ -z "${1:-}" ]]; then
      echo "ERROR usage: 'validate.sh roadmap <slug>' requires a slug argument." >&2
      exit 2
    fi
    validate_roadmap "$1"
    ;;
  spec)
    require_config
    if [[ -z "${1:-}" ]]; then
      echo "ERROR usage: 'validate.sh spec <slug>' requires a slug argument." >&2
      exit 2
    fi
    spec_path=$(resolve_artifact_path spec "$1")
    if [[ -z "$spec_path" ]]; then
      if [[ "$1" == */* ]]; then
        err "spec($1)" "file not found at $1"
      else
        err "spec($1)" "file not found (looked at $AI_DIR/spec/$1(.md))"
      fi
    else
      validate_spec "$spec_path"
    fi
    ;;
  all)
    require_config
    # `all` validates every artifact that EXISTS. Tolerates an empty (or
    # missing) .task/task/ directory.
    if [[ -d "$AI_DIR/task" ]]; then
      for f in "$AI_DIR/task"/*.md; do
        [[ -f "$f" ]] || continue
        validate_task "$f"
      done
    fi
    if [[ -d "$AI_DIR/roadmap" ]]; then
      for f in "$AI_DIR/roadmap"/*.md; do
        [[ -f "$f" ]] || continue
        validate_roadmap "$f"
      done
    fi
    if [[ -d "$AI_DIR/spec" ]]; then
      for f in "$AI_DIR/spec"/*.md; do
        [[ -f "$f" ]] || continue
        validate_spec "$f"
      done
    fi
    ;;
  ""|-h|--help|help)
    cat >&2 <<'EOF'
Usage:
  validate.sh task <slug>     — validate .task/task/<slug>.md
  validate.sh roadmap <slug>  — validate a roadmap file
  validate.sh spec <slug>     — validate .task/spec/<slug>.md
  validate.sh all             — every task + roadmap + spec file

<slug> is the filename (with or without the .md suffix), looked up under
.task/ only. An argument holding a `/` is taken as an explicit path instead.

Exit codes: 0 ok, 1 validation errors, 2 usage / precondition.
EOF
    exit 2
    ;;
  *)
    echo "ERROR usage: unknown subcommand '$cmd'. Run 'validate.sh --help'." >&2
    exit 2
    ;;
esac

if (( ERRORS > 0 )); then
  echo "FAIL $ERRORS error(s), $WARNS warning(s)" >&2
  exit 1
fi

echo "OK 0 errors, $WARNS warning(s)" >&2
exit 0
