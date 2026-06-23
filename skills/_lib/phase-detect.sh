#!/usr/bin/env bash
# phase-detect.sh — Detect the next pipeline phase by inspecting workspace state.
#
# Used by /task:design and /task:build orchestrator SKILL.md to dispatch to
# the right companion phase file (skills/<design|build>/phases/<phase>.md)
# without forcing the user to pass --phase.
#
# Usage:
#   PHASE=$(bash "${CLAUDE_SKILL_DIR}/../_lib/phase-detect.sh" <design|build>)
#
# Output: one of (on stdout):
#   open | idea | blueprint | refine-prompt     (for design)
#   implement | audit | done                    (for build)
#
# Special values:
#   refine-prompt — design's plan.md exists; orchestrator should ask whether
#                   the user wants to refine, not auto-enter refine.
#   done          — build is complete; orchestrator should suggest /task:ship.
#
# Detection logic (first match wins):
#   design:
#     1. no .task-current OR no task.md           → open
#     2. ## Description body empty                → idea
#     3. no plan.md                               → blueprint
#     4. plan.md exists                           → refine-prompt
#
#   build:
#     1. plan.md missing                                 → error (call /task:design first)
#     2. no summary.md (implement not yet run)            → implement
#     3. audit.md missing OR any "pending fix" in file   → audit
#     4. all complete                                    → done
#     (summary.md present but no diff vs HEAD → not a reroute; emits a stderr WARN.)
#
#   Note on the "pending fix" scan: the parser greps the whole file, not just
#   the last `## Iteration N` block. The audit phase rewrites earlier
#   `pending fix` strings to `Fixed` / `Skipped: …` when applying fixes, so in
#   practice only the latest iteration can hold a residual one — but the
#   parser stays whole-file out of paranoia (a producer that leaves stale
#   `pending fix` strings in earlier iterations would otherwise route the
#   orchestrator to `done` with unresolved findings).
#
# Exit codes:
#   0 — phase printed to stdout
#   1 — error (missing precondition, e.g. plan.md for build)
#   2 — usage error

set -u

SCOPE="${1:?Usage: phase-detect.sh <design|build>}"

# --- Bootstrap: locate _lib/ via symlink-tolerant idiom ---
__BOOT="${BASH_SOURCE[0]}"
while [ -L "$__BOOT" ]; do D=$(cd "$(dirname "$__BOOT")" && pwd); __BOOT=$(readlink "$__BOOT"); [[ "$__BOOT" != /* ]] && __BOOT="$D/$__BOOT"; done
SCRIPT_DIR=$(cd "$(dirname "$__BOOT")" && pwd)
# shellcheck source=resolve-ws.sh
source "$SCRIPT_DIR/resolve-ws.sh"

# Resolve WS_DIR best-effort. For design's "open" phase there's no workspace yet,
# so we accept a failing resolve and treat it as "open".
if ! resolve_ws 2>/dev/null; then
  if [[ "$SCOPE" == "design" ]]; then
    echo "open"
    exit 0
  fi
  echo "ERROR: no active task. Run /task:design first to open a task." >&2
  exit 1
fi

TASK_FILE="$WS_DIR/task.md"
PLAN_FILE="$WS_DIR/plan.md"
SUMMARY_FILE="$WS_DIR/summary.md"
AUDIT_FILE="$WS_DIR/audit.md"

# --- design scope ---
if [[ "$SCOPE" == "design" ]]; then
  if [[ ! -f "$TASK_FILE" ]]; then
    echo "open"
    exit 0
  fi

  # Description body — strip HTML comments and whitespace, then check emptiness.
  # Newlines are flattened to spaces BEFORE the strip so a multi-line comment
  # (`<!--\n guidance \n-->`) collapses onto one line and is removed too — a
  # line-wise sed would leave its body behind and misroute an empty task.
  # Non-greedy match: a comment runs from `<!--` to the FIRST `-->`, so two
  # comments (`<!-- a --> text <!-- b -->`) do not also swallow the text
  # between them. The `[^-]*(-[^-]+)*` body permits internal single `-`
  # characters while still stopping at the first `-->`.
  DESC_CONTENT=$(awk '
    /^## Description[[:space:]]*$/ { in_desc = 1; next }
    in_desc && /^## / { exit }
    in_desc { print }
  ' "$TASK_FILE" | tr '\n' ' ' | sed -E 's/<!--[^-]*(-[^-]+)*-->//g' | tr -d '[:space:]')

  if [[ -z "$DESC_CONTENT" ]]; then
    echo "idea"
    exit 0
  fi

  if [[ ! -f "$PLAN_FILE" ]]; then
    echo "blueprint"
    exit 0
  fi

  # plan.md exists — orchestrator should prompt for refine, not auto-enter.
  echo "refine-prompt"
  exit 0
fi

# --- build scope ---
if [[ "$SCOPE" == "build" ]]; then
  if [[ ! -f "$PLAN_FILE" ]]; then
    echo "ERROR: plan.md not found at $PLAN_FILE. Run /task:design first." >&2
    exit 1
  fi

  # Implement has not run until it leaves summary.md. Route to implement only
  # when that marker is absent — NOT merely because there is no diff vs HEAD: a
  # completed implement whose changes were committed or stashed leaves no diff,
  # and re-routing there would re-materialize plan steps over already-correct code.
  if [[ ! -f "$SUMMARY_FILE" ]]; then
    echo "implement"
    exit 0
  fi

  # summary.md present — implement is done. If the diff is empty, warn (audit
  # operates on the diff) but do not loop back to implement.
  if git diff --quiet HEAD 2>/dev/null; then
    echo "WARN: summary.md present but no diff vs HEAD — audit will see an empty diff." >&2
  fi

  # audit gate: audit.md missing OR any "pending fix" anywhere in file
  # (whole-file scan — see header docstring "Note on the \"pending fix\" scan").
  if [[ ! -f "$AUDIT_FILE" ]] || grep -q "pending fix" "$AUDIT_FILE" 2>/dev/null; then
    echo "audit"
    exit 0
  fi

  echo "done"
  exit 0
fi

echo "ERROR: unknown scope '$SCOPE'. Use 'design' or 'build'." >&2
exit 2
