#!/usr/bin/env bash
# auto-roadmap-helpers.sh — Shared helpers for `/task:auto-roadmap` Substeps.
#
# Three functions centralise inline bash that `skills/auto-roadmap/SKILL.md`
# previously embedded as ≥6-line snippets:
#
#   extract_implement_model <plan-path>
#     Print the `Implement-Model:` value (`opus`/`sonnet`/`haiku`) on stdout
#     and exit 0. Exit 1 with stderr message on miss / malformed / multiple
#     matches. Used by the item-runner (its Step 3) between design-runner OK
#     and build-runner spawn — it passes the value as `Agent.model` override.
#
#   refresh_roadmap_mtime <roadmap-path>
#     Print the file's mtime as Unix epoch on stdout (BSD `stat -f '%m'` with
#     GNU `stat -c '%Y'` fallback). Used by the item-runner after a successful
#     `--next` (subtask-transition) ship; the item-runner returns the value in
#     its digest so the driver's next Substep 3.1 race check sees the
#     close-induced bump as legitimate.
#
#   record_orchestrator_fail <error-log> <item> <reason>
#     Thin wrapper around `fail-log.sh orchestrator-fail` for the two
#     item-runner-side failure sites that do not originate in a child subagent
#     (MODEL_EXTRACT at item-runner Step 3 and AUDIT_LIMIT at item-runner
#     Step 5). The
#     reason is passed in the `subagent_status` slot — reusing that slot
#     keeps the on-disk shape uniform across postmortem readers, per
#     `docs/spec/auto-roadmap.md` § Failure protocol. The error-log path
#     itself is reused as `resolved_path`, and `.task-current present` is
#     hard-coded `yes` (both call sites only fire after `.task-current` has
#     been written by the first item's design-runner Open).
#
# Dual usage. Source for functions or run directly:
#
#   # As library:
#   source "$CLAUDE_PLUGIN_ROOT/skills/_lib/auto-roadmap-helpers.sh"
#   IMPLEMENT_MODEL=$(extract_implement_model "$PLAN_PATH")
#
#   # As executable (from SKILL.md):
#   IMPLEMENT_MODEL=$(bash "$CLAUDE_PLUGIN_ROOT/skills/_lib/auto-roadmap-helpers.sh" \
#                       extract_implement_model "$PLAN_PATH") || abort …
#
# Sourcing this file does NOT set `set -euo pipefail` — the caller's job.
# The exec-path entry point at the bottom sets it explicitly.

# --- extract_implement_model <plan-path> ---
extract_implement_model() {
  local plan_path=$1
  if [[ ! -f "$plan_path" ]]; then
    echo "ERROR: plan.md not found at $plan_path" >&2
    return 1
  fi
  local matches
  # grep returns 1 on no-match — mask it so the empty-string check below runs
  # under `set -e` (the exec-path enables `set -euo pipefail`).
  matches=$(grep -E '^Implement-Model:[[:space:]]+(opus|sonnet|haiku)[[:space:]]*$' "$plan_path" || true)
  if [[ -z "$matches" ]]; then
    echo "ERROR: Implement-Model: stamp missing or malformed in $plan_path" >&2
    return 1
  fi
  local count
  count=$(printf '%s\n' "$matches" | wc -l | tr -d '[:space:]')
  if [[ "$count" -gt 1 ]]; then
    echo "ERROR: multiple Implement-Model: lines in $plan_path (found $count)" >&2
    return 1
  fi
  printf '%s\n' "$matches" | sed -E 's/^Implement-Model:[[:space:]]+([a-z]+)[[:space:]]*$/\1/'
}

# --- refresh_roadmap_mtime <roadmap-path> ---
# Thin wrapper that delegates to `roadmap.sh:roadmap_mtime` so the BSD `stat
# -f '%m'` / GNU `stat -c '%Y'` fallback chain (and the `"0"` final fallback
# that makes race checks fail loud on a missing file) lives in exactly one
# place. Exposed here so SKILL.md callers have a single auto-roadmap helper
# script to source rather than two.
refresh_roadmap_mtime() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  # shellcheck source=/dev/null
  source "$script_dir/roadmap.sh"
  roadmap_mtime "$1"
}

# --- record_orchestrator_fail <error-log> <item> <reason> ---
record_orchestrator_fail() {
  local error_log=$1
  local item=$2
  local reason=$3
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  bash "$script_dir/fail-log.sh" orchestrator-fail \
    "$error_log" "$item" "$reason" "$error_log" yes
}

# ---------------- Exec-path dispatch ----------------
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail
  case "${1:-}" in
    extract_implement_model)
      shift
      if [[ $# -lt 1 ]]; then
        echo "Usage: auto-roadmap-helpers.sh extract_implement_model <plan-path>" >&2
        exit 2
      fi
      extract_implement_model "$@"
      ;;
    refresh_roadmap_mtime)
      shift
      if [[ $# -lt 1 ]]; then
        echo "Usage: auto-roadmap-helpers.sh refresh_roadmap_mtime <roadmap-path>" >&2
        exit 2
      fi
      refresh_roadmap_mtime "$@"
      ;;
    record_orchestrator_fail)
      shift
      if [[ $# -lt 3 ]]; then
        echo "Usage: auto-roadmap-helpers.sh record_orchestrator_fail <error-log> <item> <reason>" >&2
        exit 2
      fi
      record_orchestrator_fail "$@"
      ;;
    ""|-h|--help|help)
      cat >&2 <<'EOF'
Usage:
  auto-roadmap-helpers.sh extract_implement_model <plan-path>
  auto-roadmap-helpers.sh refresh_roadmap_mtime  <roadmap-path>
  auto-roadmap-helpers.sh record_orchestrator_fail <error-log> <item> <reason>

Notes:
  - extract_implement_model exits 1 on miss / malformed / multi-match.
  - refresh_roadmap_mtime prints epoch via BSD `stat -f '%m'` with GNU
    `stat -c '%Y'` fallback.
  - record_orchestrator_fail forwards to fail-log.sh orchestrator-fail
    with the reason in the subagent_status slot (orchestrator-side
    failures reuse the slot — see docs/spec/auto-roadmap.md).
EOF
      exit 2
      ;;
    *)
      echo "auto-roadmap-helpers.sh: unknown subcommand '$1'" >&2
      exit 2
      ;;
  esac
fi
