#!/usr/bin/env bash
# validate.sh — Validate the format of task-pipeline artifacts.
#
# Usage:
#   validate.sh task <slug>     — validate .task/task/<slug>.md
#   validate.sh roadmap <slug>  — validate a roadmap file
#   validate.sh spec <slug>     — validate .task/spec/<slug>.md
#   validate.sh all             — every task + roadmap + spec file
#
# v3 is flat: <slug> is both the filename and the identity — there is no
# task-id, no workspace, no active-task pointer. This is an OPTIONAL
# self-check; no hook calls it. A task/roadmap `Spec: <slug>` header that
# doesn't resolve to a .task/spec/<slug>.md is reported as a WARN (dangling
# reference), never an ERROR — the only cross-file check, and advisory only.
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

# AI_DIR is resolved by `find_ai_dir` (defined in resolve-ws.sh, sourced below)
# — a git-style upward walk so validation works from any subdir, not only the
# project root. It is deliberately NOT hardcoded to `.task` here: pinning it
# would pre-empt the walk.
ERRORS=0
WARNS=0

err() { echo "ERROR $1: $2" >&2; ERRORS=$((ERRORS + 1)); }
warn() { echo "WARN $1: $2" >&2; WARNS=$((WARNS + 1)); }

# Locate this script's directory via the symlink-tolerant idiom used elsewhere
# in the pipeline, then source the shared helpers. validate.sh is the one
# helper that does NOT go through `_lib/preamble.sh` — its issue collection /
# exit semantics differ from the standard `set -euo pipefail` shape. So we
# source `_lib/resolve-ws.sh` and `_lib/roadmap.sh` directly here.
SRC="${BASH_SOURCE[0]}"
while [ -L "$SRC" ]; do D=$(cd "$(dirname "$SRC")" && pwd); SRC=$(readlink "$SRC"); [[ "$SRC" != /* ]] && SRC="$D/$SRC"; done
SCRIPT_DIR=$(cd "$(dirname "$SRC")" && pwd)
# shellcheck source=../_lib/resolve-ws.sh
source "$SCRIPT_DIR/../_lib/resolve-ws.sh"
# shellcheck source=../_lib/roadmap.sh
source "$SCRIPT_DIR/../_lib/roadmap.sh"

# --- Precondition: config.md ---
require_config() {
  # Resolve AI_DIR via the upward walk before reading config.md. find_ai_dir
  # is idempotent (no-op once AI_DIR is set).
  find_ai_dir
  if [[ ! -f "$AI_DIR/config/config.md" ]]; then
    echo "ERROR precondition: $AI_DIR/config/config.md not found." >&2
    exit 2
  fi
}

# --- resolve_task_path <arg> ---
# Echoes the resolved task path on stdout, or empty string if no match.
# Lookup order: explicit path → $AI_DIR/task/<arg> → $AI_DIR/task/<arg>.md.
resolve_task_path() {
  local arg="$1"
  if [[ -f "$arg" ]]; then echo "$arg"; return; fi
  if [[ -f "$AI_DIR/task/$arg" ]]; then echo "$AI_DIR/task/$arg"; return; fi
  if [[ -f "$AI_DIR/task/$arg.md" ]]; then echo "$AI_DIR/task/$arg.md"; return; fi
  echo ""
}

# --- resolve_spec_path <arg> ---
# Echoes the resolved spec path on stdout, or empty string if no match.
# Lookup order: explicit path → $AI_DIR/spec/<arg> → $AI_DIR/spec/<arg>.md.
resolve_spec_path() {
  local arg="$1"
  if [[ -f "$arg" ]]; then echo "$arg"; return; fi
  if [[ -f "$AI_DIR/spec/$arg" ]]; then echo "$AI_DIR/spec/$arg"; return; fi
  if [[ -f "$AI_DIR/spec/$arg.md" ]]; then echo "$AI_DIR/spec/$arg.md"; return; fi
  echo ""
}

# --- check_spec_refs <file> <label> ---
# WARN (never ERROR) for any `Spec: <slug>` header in <file> that does not
# resolve to an existing .task/spec/<slug>.md. This is the only cross-file
# check in the pipeline, and it is advisory — validate.sh is not a gate.
# Runs in the caller's shell (not a subshell), so WARNS is updated directly.
check_spec_refs() {
  local file="$1" label="$2" slug
  [[ -f "$file" ]] || return
  while IFS= read -r slug; do
    [[ -z "$slug" ]] && continue
    if [[ ! -f "$AI_DIR/spec/$slug.md" ]]; then
      warn "$label" "Spec: $slug — no such spec at $AI_DIR/spec/$slug.md (dangling reference)"
    fi
  done < <(grep -E '^Spec:[[:space:]]' "$file" 2>/dev/null | sed -E 's/^Spec:[[:space:]]*//; s/[[:space:]]+$//')
}

# ---------------- task.md ----------------
# One format for both to-task and to-plan output:
#   line 1   — `# <Title>` (plain title, no task-id)
#   `---`    — separator between header and body
#   `## Description` — always present
#   `## Plan`  — OPTIONAL (only to-plan writes it); if present, require >=1
#                `### Step N:` block.
#   `## Tests` — OPTIONAL; if present, require >=1 `### Test N:` block.
validate_task() {
  local file="$1"
  local label="task($file)"

  if [[ ! -f "$file" ]]; then
    err "$label" "file not found at $file"
    return
  fi

  local first_line
  first_line=$(head -1 "$file")
  if ! [[ "$first_line" =~ ^\#\ .+$ ]]; then
    err "$label" "first line must match '# <Title>'; got: ${first_line:-<empty>}"
  fi

  if ! grep -qxF -- '---' "$file"; then
    err "$label" "missing '---' separator between header and Description"
  fi

  if ! grep -qE '^## Description[[:space:]]*$' "$file"; then
    err "$label" "missing '## Description' section heading"
  fi

  # `## Plan` is OPTIONAL (only to-plan writes it). If present, it must carry
  # at least one `### Step N:` block.
  if grep -qE '^## Plan[[:space:]]*$' "$file"; then
    if ! awk '/^## Plan[[:space:]]*$/{flag=1; next} /^## /{flag=0} flag && /^### Step [0-9]+/{found=1} END{exit !found}' "$file"; then
      err "$label" "'## Plan' section is present but contains no '### Step N:' blocks"
    fi
  fi

  # `## Tests` is OPTIONAL. If present, it must carry at least one `### Test N:`.
  if grep -qE '^## Tests[[:space:]]*$' "$file"; then
    if ! awk '/^## Tests[[:space:]]*$/{flag=1; next} /^## /{flag=0} flag && /^### Test [0-9]+/{found=1} END{exit !found}' "$file"; then
      err "$label" "'## Tests' section is present but contains no '### Test N:' blocks"
    fi
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

  if [[ ! -f "$file" ]]; then
    err "$label" "file not found at $file"
    return
  fi

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
# Resolution order is implemented in `_lib/roadmap.sh:resolve_roadmap_path`.

validate_roadmap() {
  local raw="$1"
  local file
  file=$(resolve_roadmap_path "$raw")
  if [[ -z "$file" ]]; then
    err "roadmap($raw)" "file not found (looked at $raw, $AI_DIR/roadmap/$raw(.md))"
    return
  fi
  local label
  label="roadmap($file)"

  # Dangling `Spec:` header references → WARN (advisory, not an error).
  check_spec_refs "$file" "$label"

  # Find task headings: `### - [x] | - [ ] | - [~] | - [>] | - [-] N. <title>`.
  # Checkbox prefix is REQUIRED — the roadmap-to-workflow driver's auto-mark
  # and item selection both rely on it.
  if ! grep -qE '^### - \[[ x~>-]\] [0-9]+\. .+$' "$file"; then
    err "$label" "no task headings matching '### - [ ] N. <title>' — every item must carry a checkbox prefix (roadmap-to-workflow auto-mark and item selection rely on it)"
    return
  fi

  awk -v label="$label" '
    function flush_block() {
      if (in_block == 0) return
      if (!has_context)  print "ERROR " label ": Task " task_no " missing '\''### Context'\'' sub-heading"
      if (!has_goal)     print "ERROR " label ": Task " task_no " missing '\''### Goal'\'' sub-heading"
      if (!has_outcomes) print "ERROR " label ": Task " task_no " missing '\''### Outcomes'\'' sub-heading"
      if (!has_accept)   print "ERROR " label ": Task " task_no " missing '\''### Acceptance criteria'\'' sub-heading"
      in_block = 0
      has_ready = has_context = has_goal = has_outcomes = has_invariants = has_accept = 0
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
      print "ERROR " label ": Task " m " missing checkbox prefix '\''- [ ]'\''; roadmap-to-workflow auto-mark and item selection require every item to carry a checkbox"
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
        # (`> ### Goal`, etc.) — to-plan / the executing session strip `> `
        # before parsing, so a top-level `### Goal` would not be recognized as
        # the description body. Require the `> ` prefix; do not accept the
        # bare form.
        if ($0 ~ /^>[[:space:]]+### Context[[:space:]]*$/) has_context = 1
        if ($0 ~ /^>[[:space:]]+### Goal[[:space:]]*$/) has_goal = 1
        if ($0 ~ /^>[[:space:]]+### Outcomes[[:space:]]*$/) has_outcomes = 1
        if ($0 ~ /^>[[:space:]]+### Invariants[[:space:]]*$/) has_invariants = 1
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
MARKER_FILE=$(mktemp 2>/dev/null || echo "/tmp/task-validate-$$.marker")
: > "$MARKER_FILE"

cmd="${1:-}"
shift || true
case "$cmd" in
  task)
    require_config
    if [[ -z "${1:-}" ]]; then
      echo "ERROR usage: 'validate.sh task <slug>' requires a slug argument." >&2
      rm -f "$MARKER_FILE"
      exit 2
    fi
    validate_task "$(resolve_task_path "$1")"
    ;;
  roadmap)
    require_config
    if [[ -z "${1:-}" ]]; then
      echo "ERROR usage: 'validate.sh roadmap <slug>' requires a slug argument." >&2
      rm -f "$MARKER_FILE"
      exit 2
    fi
    validate_roadmap "$1"
    ;;
  spec)
    require_config
    if [[ -z "${1:-}" ]]; then
      echo "ERROR usage: 'validate.sh spec <slug>' requires a slug argument." >&2
      rm -f "$MARKER_FILE"
      exit 2
    fi
    spec_path=$(resolve_spec_path "$1")
    if [[ -z "$spec_path" ]]; then
      err "spec($1)" "file not found (looked at $1, $AI_DIR/spec/$1(.md))"
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
        # Skip any orphaned v2 roadmap sidecar (`<slug>.spec.md`). Specs now
        # live in .task/spec/ — a `.spec.md` under roadmap/ is not a roadmap.
        case "$f" in *.spec.md) continue ;; esac
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

<slug> is the filename (with or without the .md suffix); it is also accepted
as an explicit path.

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
