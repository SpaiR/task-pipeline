#!/usr/bin/env bash
# validate.sh — Validate the format of task-pipeline artifacts.
#
# Usage:
#   validate.sh task [<task-id>]      — validate .task/workspace/<task-id>/task.md
#   validate.sh plan [<task-id>]      — validate .task/workspace/<task-id>/plan.md
#   validate.sh todo <path|slug>      — validate a roadmap file (legacy alias of `roadmap`)
#   validate.sh roadmap <path|slug>   — validate a roadmap file
#   validate.sh all                   — task + plan (when present) + every .task/roadmap/*.md
#
# For `task` and `plan`, the workspace subfolder is resolved via _lib/resolve-ws.sh:
# $TASK_ID_OVERRIDE > positional <task-id> > .task-current. The `all` form
# tolerates a missing .task-current and simply skips workspace validation
# (used by the PreToolUse hook, which fires outside any active umbrella too).
#
# Exit codes:
#   0 — all checks passed
#   1 — at least one validation error
#   2 — usage error or missing precondition (config.md absent)
#
# Output: each issue is printed on its own line as
#     <severity> <artifact>: <message>
# where <severity> is ERROR (counted toward exit 1) or WARN (informational).
# A final summary line is always printed.

set -u
# Note: do NOT use `set -e` — we collect issues and report them all at once
# rather than aborting on the first failure.

AI_DIR=".task"
# WS_DIR is populated by resolve_ws() (sourced below) before validate_task /
# validate_plan run. The `all` subcommand calls resolve_ws() best-effort and
# skips workspace validation if no .task-current is present.
ERRORS=0
WARNS=0

err() { echo "ERROR $1: $2" >&2; ERRORS=$((ERRORS + 1)); }
warn() { echo "WARN $1: $2" >&2; WARNS=$((WARNS + 1)); }

# Locate this script's directory via the symlink-tolerant idiom used elsewhere
# in the pipeline, then source the shared workspace resolver. validate.sh is
# the one helper that does NOT go through `_lib/preamble.sh` — its `all` form
# needs best-effort `resolve_ws 2>/dev/null`, and its issue collection / exit
# semantics differ from the standard `set -euo pipefail` shape. So we source
# `_lib/resolve-ws.sh` and `_lib/roadmap.sh` directly here.
SRC="${BASH_SOURCE[0]}"
while [ -L "$SRC" ]; do D=$(cd "$(dirname "$SRC")" && pwd); SRC=$(readlink "$SRC"); [[ "$SRC" != /* ]] && SRC="$D/$SRC"; done
SCRIPT_DIR=$(cd "$(dirname "$SRC")" && pwd)
# shellcheck source=../_lib/resolve-ws.sh
source "$SCRIPT_DIR/../_lib/resolve-ws.sh"
# Opt in to legacy `.task/todo/` WARN — validate.sh is the user-facing surface
# for the deprecation message; auto-roadmap-context.sh stays silent (it calls
# validate.sh first, so the WARN already prints exactly once).
ROADMAP_WARN_ON_LEGACY=1
# shellcheck source=../_lib/roadmap.sh
source "$SCRIPT_DIR/../_lib/roadmap.sh"

# --- Precondition: config.md ---
require_config() {
  if [[ ! -f "$AI_DIR/config/config.md" ]]; then
    echo "ERROR precondition: $AI_DIR/config/config.md not found. Run /task:bootstrap first." >&2
    exit 2
  fi
}

# ---------------- task.md ----------------
validate_task() {
  local file="$WS_DIR/task.md"
  local label="task.md"

  if [[ ! -f "$file" ]]; then
    err "$label" "file not found at $file"
    return
  fi

  local first_line
  first_line=$(head -1 "$file")
  if ! [[ "$first_line" =~ ^\#\ \[[^]]+\]\ .+$ ]]; then
    err "$label" "first line must match '# [task-id] <title>'; got: ${first_line:-<empty>}"
  fi

  if ! grep -qxF -- '---' "$file"; then
    err "$label" "missing '---' separator between header and Description"
  fi

  if ! grep -qE '^## Description[[:space:]]*$' "$file"; then
    err "$label" "missing '## Description' section heading"
  fi

  # Soft check: roadmap-mode header pairs `Roadmap:` with `Source item:`.
  # `/task:ship`'s auto-mark needs both; if only one is present, surface a
  # warning so the user knows auto-mark will silently skip. The full shape
  # `Source item: #<N> — <title>` is also enforced as a separate WARN — close
  # only needs `#<N>` to flip, but the title is the audit trail back to the
  # roadmap item and is part of the documented contract.
  local has_roadmap has_source has_full_source
  has_roadmap=$(awk '/^---[[:space:]]*$/{exit} /^Roadmap: /{print "1"; exit}' "$file")
  if [[ "$has_roadmap" == "1" ]]; then
    has_source=$(awk '/^---[[:space:]]*$/{exit} /^Source item: #[0-9][0-9]*/{print "1"; exit}' "$file")
    if [[ "$has_source" != "1" ]]; then
      warn "$label" "'Roadmap:' line present in header but 'Source item: #<N> — <title>' missing; /task:ship auto-mark will skip this umbrella"
    else
      has_full_source=$(awk '/^---[[:space:]]*$/{exit} /^Source item: #[0-9][0-9]* — [^[:space:]]/{print "1"; exit}' "$file")
      if [[ "$has_full_source" != "1" ]]; then
        warn "$label" "'Source item:' line lacks the documented '#<N> — <item title>' shape; auto-mark still works on the number, but the audit trail back to the roadmap item is incomplete"
      fi
    fi
  fi
}

# ---------------- plan.md ----------------
validate_plan() {
  local file="$WS_DIR/plan.md"
  local label="plan.md"

  if [[ ! -f "$file" ]]; then
    err "$label" "file not found at $file"
    return
  fi

  local first_line
  first_line=$(head -1 "$file")
  if ! [[ "$first_line" =~ ^\#\ Plan:\ .+$ ]]; then
    err "$label" "first line must match '# Plan: <title>'; got: ${first_line:-<empty>}"
  fi

  if ! grep -qE '^## Steps[[:space:]]*$' "$file"; then
    err "$label" "missing '## Steps' section heading"
    return
  fi

  if ! grep -qE '^## Verification[[:space:]]*$' "$file"; then
    err "$label" "missing '## Verification' section heading"
  fi

  # `Implement-Model: <opus|sonnet|haiku>` is mandatory (blueprint/SKILL.md
  # Step 3). Load-bearing for `/task:auto-roadmap`: the orchestrator reads this
  # header between design-runner and build-runner spawns and passes the value
  # as `Agent.model` override when spawning `auto-roadmap-build-runner`.
  # Harmless in manual flows where no runtime consumer keys off it.
  if ! grep -qE '^Implement-Model:[[:space:]]+(opus|sonnet|haiku)[[:space:]]*$' "$file"; then
    err "$label" "missing or malformed 'Implement-Model:' header (expected '^Implement-Model: <opus|sonnet|haiku>\$' anywhere in the file; blueprint/SKILL.md Step 3 places it between '# Plan:' and '## Scope')"
  fi

  # `## Risks` is optional — informational only, no downstream consumer.

  # Walk the file step-by-step. A step block starts at `### Step ` and ends
  # at the next `### Step `, `### Test `, `## ` heading, or EOF.
  awk -v label="$label" '
    BEGIN { step_count = 0; in_step = 0; step_no = ""; goal = ""; touches = ""; in_touches_list = 0; }

    function flush_step() {
      if (in_step == 0) return
      step_count++
      if (goal == "")    print "ERROR " label ": Step " step_no " missing non-empty Goal:"
      if (touches == "") print "ERROR " label ": Step " step_no " missing non-empty Touches:"
      else if (touches ~ /\.\.\./) print "ERROR " label ": Step " step_no " Touches contains '\''...'\'' placeholder"
      in_step = 0; step_no = ""; goal = ""; touches = ""; in_touches_list = 0
    }

    /^### Step / {
      flush_step()
      in_step = 1
      step_no = $0
      sub(/^### Step[[:space:]]+/, "", step_no)
      sub(/[:.].*$/, "", step_no)
      next
    }

    /^### / || /^## / {
      flush_step()
      next
    }

    {
      if (in_step) {
        line = $0

        # Continuation of a list-form Touches block (lines under "- Touches:").
        # Indented "- item" lines accumulate into touches; blank lines are
        # tolerated; anything else ends the list and falls through to normal
        # field matching below.
        if (in_touches_list) {
          if (line ~ /^[[:space:]]*$/) { next }
          else if (line ~ /^[[:space:]]+-[[:space:]]+[^[:space:]]/) {
            rest = line
            sub(/^[[:space:]]+-[[:space:]]+/, "", rest)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", rest)
            if (rest != "") {
              if (touches == "") touches = rest
              else touches = touches ", " rest
            }
            next
          }
          else {
            in_touches_list = 0
          }
        }

        # Match "Goal:" or "- Goal:" (any leading whitespace)
        if (match(line, /^[[:space:]]*-?[[:space:]]*Goal:[[:space:]]*/)) {
          rest = substr(line, RSTART + RLENGTH)
          gsub(/^[[:space:]]+|[[:space:]]+$/, "", rest)
          if (rest != "") goal = rest
        }
        else if (match(line, /^[[:space:]]*-?[[:space:]]*Touches:[[:space:]]*/)) {
          rest = substr(line, RSTART + RLENGTH)
          gsub(/^[[:space:]]+|[[:space:]]+$/, "", rest)
          if (rest != "") { touches = rest; in_touches_list = 0 }
          else { in_touches_list = 1 }
        }
      }
    }

    END {
      flush_step()
      if (step_count == 0) print "ERROR " label ": no `### Step N:` blocks found under `## Steps`"
    }
  ' "$file" | while IFS= read -r line; do
      # Re-emit from awk; classify by prefix.
      if [[ "$line" == ERROR* ]]; then
        echo "$line" >&2
        # Count via marker file because subshell breaks ERRORS counter.
        echo x >> "$MARKER_FILE"
      else
        echo "$line" >&2
      fi
  done

  # Tests section: if present and non-empty, must have at least one `### Test `
  if grep -qE '^## Tests[[:space:]]*$' "$file"; then
    if ! awk '/^## Tests/{flag=1; next} /^## /{flag=0} flag && /^### Test /{found=1} END{exit !found}' "$file"; then
      err "$label" "'## Tests' section is present but contains no '### Test N:' blocks"
    fi
  fi
}

# ---------------- roadmap file ----------------
# Resolution order is implemented in `_lib/roadmap.sh:resolve_roadmap_path`.
# We opt in to its `ROADMAP_WARN_ON_LEGACY=1` mode at source time (above), so
# legacy `.task/todo/<slug>(.md)` paths still resolve but emit a stderr WARN.
# The legacy branch is kept for one release after the .task/todo/ →
# .task/roadmap/ rename — remove in 0.2.x in lockstep with the resolver.

validate_roadmap() {
  local raw="$1"
  local file
  file=$(resolve_roadmap_path "$raw")
  if [[ -z "$file" ]]; then
    err "roadmap($raw)" "file not found (looked at $raw, $AI_DIR/roadmap/$raw(.md), $AI_DIR/todo/$raw(.md))"
    return
  fi
  local label
  label="roadmap($file)"

  # Find task headings: `### - [x] | - [ ] | - [~] | - [>] | - [-] N. <title>`.
  # Checkbox prefix is REQUIRED — `/task:ship` auto-mark and `/task:design
  # --from` auto-pick both rely on it.
  if ! grep -qE '^### - \[[ x~>-]\] [0-9]+\. .+$' "$file"; then
    err "$label" "no task headings matching '### - [ ] N. <title>' — every item must carry a checkbox prefix (close auto-mark and open auto-pick rely on it)"
    return
  fi

  awk -v label="$label" '
    function flush_block() {
      if (in_block == 0) return
      if (!has_ready)    print "ERROR " label ": Task " task_no " missing '\''**Ready description:**'\'' line"
      if (!has_context)  print "ERROR " label ": Task " task_no " missing '\''### Context'\'' sub-heading"
      if (!has_goal)     print "ERROR " label ": Task " task_no " missing '\''### Goal'\'' sub-heading"
      if (!has_outcomes) print "ERROR " label ": Task " task_no " missing '\''### Outcomes'\'' sub-heading"
      if (!has_accept)   print "ERROR " label ": Task " task_no " missing '\''### Acceptance criteria'\'' sub-heading"
      in_block = 0
      has_ready = has_context = has_goal = has_outcomes = has_accept = 0
      task_no = ""
    }

    /^### - \[[ x~>-]\] [0-9]+\. / {
      flush_block()
      in_block = 1
      m = $0
      sub(/^### - \[[ x~>-]\] /, "", m)
      sub(/\..*$/, "", m)
      task_no = m
      next
    }

    /^### [0-9]+\. / {
      flush_block()
      m = $0
      sub(/^### /, "", m)
      sub(/\..*$/, "", m)
      print "ERROR " label ": Task " m " missing checkbox prefix '\''- [ ]'\''; close auto-mark and open auto-pick require every item to carry a checkbox"
      next
    }

    # Stop at next `### ` heading that is NOT a sub-heading of this block.
    # Sub-headings inside the blockquote start with `> ### `, so they do not
    # match `^### `. Other top-level `### ` headings end the block.
    /^### / { flush_block(); next }
    /^## /  { flush_block(); next }
    /^---[[:space:]]*$/ { flush_block(); next }

    {
      if (in_block) {
        if ($0 ~ /\*\*Ready description:\*\*/) has_ready = 1
        # Sub-headings MUST be inside the `**Ready description:**` blockquote
        # (`> ### Goal`, etc.) — /task:design --from strips `> ` before parsing,
        # so a top-level `### Goal` would not be recognized as the description
        # body. Require the `> ` prefix; do not accept the bare form.
        if ($0 ~ /^>[[:space:]]+### Context[[:space:]]*$/) has_context = 1
        if ($0 ~ /^>[[:space:]]+### Goal[[:space:]]*$/) has_goal = 1
        if ($0 ~ /^>[[:space:]]+### Outcomes[[:space:]]*$/) has_outcomes = 1
        if ($0 ~ /^>[[:space:]]+### Acceptance criteria[[:space:]]*$/) has_accept = 1
      }
    }

    END { flush_block() }
  ' "$file" | while IFS= read -r line; do
      echo "$line" >&2
      [[ "$line" == ERROR* ]] && echo x >> "$MARKER_FILE"
  done
}

# ---------------- main ----------------
# Marker file collects ERROR lines from awk subshells (counter doesn't survive).
MARKER_FILE=$(mktemp 2>/dev/null || echo "/tmp/task:validate-$$.marker")
: > "$MARKER_FILE"

cmd="${1:-}"
shift || true
case "$cmd" in
  task)
    require_config
    # Resolve WS_DIR via $TASK_ID_OVERRIDE > positional > .task-current.
    # Strict: fail if no active task is resolvable (the explicit `task` form
    # is only invoked when the caller already expects a workspace to exist).
    resolve_ws "$@" || exit 2
    validate_task
    ;;
  plan)
    require_config
    resolve_ws "$@" || exit 2
    validate_plan
    ;;
  todo|roadmap)
    require_config
    if [[ -z "${1:-}" ]]; then
      echo "ERROR usage: 'validate.sh $cmd <path|slug>' requires a path argument." >&2
      rm -f "$MARKER_FILE"
      exit 2
    fi
    validate_roadmap "$1"
    ;;
  all)
    require_config
    # `all` is the hook-friendly form: validate every artifact that EXISTS.
    # Lenient on workspace resolution: PreToolUse fires on every tool call,
    # including before /task:design creates .task-current. /task:auto-roadmap Step 0 also
    # preconditions on the absence of an active task. If the resolver fails,
    # silently skip workspace validation; roadmap validation runs regardless.
    if resolve_ws 2>/dev/null; then
      [[ -f "$WS_DIR/task.md" ]] && validate_task
      [[ -f "$WS_DIR/plan.md" ]] && validate_plan
    fi
    # Validate roadmap files. Prefer .task/roadmap/, fall back to legacy .task/todo/
    # for one release so existing repos keep working before they rename.
    # Skip the sidecars: `<slug>.refine.md` (refine-log) and `<slug>.spec.md`
    # (spec sidecar) live in the same directory but are NOT roadmaps — they
    # carry no `### - [ ] N.` task headings and would fail validation spuriously.
    if [[ -d "$AI_DIR/roadmap" ]]; then
      for f in "$AI_DIR/roadmap"/*.md; do
        [[ -f "$f" ]] || continue
        case "$f" in *.refine.md|*.spec.md) continue ;; esac
        validate_roadmap "$f"
      done
    fi
    if [[ -d "$AI_DIR/todo" ]]; then
      echo "WARN roadmap(.task/todo/): legacy directory still present. Rename .task/todo/ → .task/roadmap/." >&2
      for f in "$AI_DIR/todo"/*.md; do
        [[ -f "$f" ]] || continue
        case "$f" in *.refine.md|*.spec.md) continue ;; esac
        validate_roadmap "$f"
      done
    fi
    ;;
  ""|-h|--help|help)
    cat >&2 <<'EOF'
Usage:
  validate.sh task [<task-id>]      — validate .task/workspace/<task-id>/task.md
  validate.sh plan [<task-id>]      — validate .task/workspace/<task-id>/plan.md
  validate.sh roadmap <path|slug>   — validate a roadmap file
  validate.sh todo <path|slug>      — legacy alias of `roadmap`
  validate.sh all                   — task + plan (when present) + every .task/roadmap/*.md

For `task` / `plan`, the workspace subfolder is resolved via:
  $TASK_ID_OVERRIDE > positional <task-id> > contents of .task-current.

Exit codes: 0 ok, 1 validation errors, 2 usage / precondition.
EOF
    rm -f "$MARKER_FILE"
    exit 2
    ;;
  *)
    echo "ERROR usage: unknown subcommand '$cmd'. Run 'validate.sh --help'." >&2
    rm -f "$MARKER_FILE"
    exit 2
    ;;
esac

# Roll up awk-emitted errors into the counter.
if [[ -f "$MARKER_FILE" ]]; then
  AWK_ERRS=$(wc -l < "$MARKER_FILE" | tr -d ' ')
  ERRORS=$((ERRORS + AWK_ERRS))
  rm -f "$MARKER_FILE"
fi

if (( ERRORS > 0 )); then
  echo "FAIL $ERRORS error(s), $WARNS warning(s)" >&2
  exit 1
fi

echo "OK 0 errors, $WARNS warning(s)" >&2
exit 0
