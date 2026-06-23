#!/usr/bin/env bash
# fail-log.sh — Shared formatter for the `auto-error.log` block protocol.
#
# Two block shapes share one parser-stable header `--- <TAG> <ISO> ---`:
#   --- FAIL <ISO> ---              (per-stage failure inside the auto-roadmap runner)
#   --- ORCHESTRATOR FAIL <ISO> --- (auto-roadmap main thread on subagent FAIL)
#
# Each block is appended to the error log; the file is never rewritten. The
# header is English regardless of `config.md` → "Language" (parser-stable).
#
# Dual usage. Source the file to get the functions, or run it directly to
# emit a block from a SKILL.md bash snippet:
#
#   # As library:
#   source "$SCRIPT_DIR/../_lib/fail-log.sh"
#   append_fail_log "$ERROR_LOG" "implement" "tests failed after one quick-fix" \
#                   --item "#$N" --stage-log "$LOG_PATH" --ws-snapshot "$WS_DIR"
#
#   # As executable (from SKILL.md / from agents):
#   bash "$CLAUDE_PLUGIN_ROOT/skills/_lib/fail-log.sh" orchestrator-fail \
#     "$ERROR_LOG" "#$N" "<verbatim status>" "<resolved path>" yes
#
# This file does NOT set `set -euo pipefail` when sourced — caller's job.
# The exec-path entry point at the bottom sets it explicitly.

# --- timestamp helper (UTC ISO 8601) ---
_fail_log_ts() {
  date -u +%FT%TZ
}

# --- append_fail_log <error_log> <stage> <reason> [--item #N] [--stage-log PATH] [--ws-snapshot DIR] ---
# Writes a `--- FAIL <ISO> ---` block. Fields after stage/reason are optional;
# stage-log appends `tail -50` of the stage log, ws-snapshot appends `ls -la`.
append_fail_log() {
  local error_log=$1
  local stage=$2
  local reason=$3
  shift 3
  local item="?"
  local stage_log=""
  local ws_snapshot=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --item) item=$2; shift 2 ;;
      --stage-log) stage_log=$2; shift 2 ;;
      --ws-snapshot) ws_snapshot=$2; shift 2 ;;
      *) shift ;;
    esac
  done
  {
    echo "--- FAIL $(_fail_log_ts) ---"
    echo "item: $item"
    echo "stage: $stage"
    echo "reason: $reason"
    if [[ -n "$stage_log" && -f "$stage_log" ]]; then
      echo ""
      echo "stage log tail ($stage_log):"
      tail -50 "$stage_log" 2>&1 || true
    fi
    if [[ -n "$ws_snapshot" ]]; then
      echo ""
      echo "$ws_snapshot snapshot:"
      ls -la "$ws_snapshot" 2>&1 || true
    fi
    echo ""
  } >> "$error_log"
}

# --- append_orchestrator_fail_log <error_log> <item> <subagent_status> <resolved_path> <task_current_present> ---
# Writes a `--- ORCHESTRATOR FAIL <ISO> ---` block. Used by `/task:auto-roadmap`
# main thread when a subagent returned FAIL or a malformed status line.
append_orchestrator_fail_log() {
  local error_log=$1
  local item=$2
  local subagent_status=$3
  local resolved_path=$4
  local task_current_present=$5
  {
    echo "--- ORCHESTRATOR FAIL $(_fail_log_ts) ---"
    echo "item: $item"
    echo "subagent status line: $subagent_status"
    echo "resolved error-log path: $resolved_path"
    echo ".task-current present: $task_current_present"
    echo ""
  } >> "$error_log"
}

# ---------------- Exec-path dispatch ----------------
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail
  case "${1:-}" in
    fail)
      shift
      if [[ $# -lt 3 ]]; then
        echo "Usage: fail-log.sh fail <error_log> <stage> <reason> [--item ...] [--stage-log ...] [--ws-snapshot ...]" >&2
        exit 2
      fi
      append_fail_log "$@"
      ;;
    orchestrator-fail)
      shift
      if [[ $# -lt 5 ]]; then
        echo "Usage: fail-log.sh orchestrator-fail <error_log> <item> <subagent_status> <resolved_path> <task_current_present>" >&2
        exit 2
      fi
      append_orchestrator_fail_log "$@"
      ;;
    ""|-h|--help|help)
      cat >&2 <<'EOF'
Usage:
  fail-log.sh fail              <error_log> <stage> <reason> [--item #N] [--stage-log PATH] [--ws-snapshot DIR]
  fail-log.sh orchestrator-fail <error_log> <item> <subagent_status> <resolved_path> <task_current_present>

Each form appends a parser-stable `--- TAG <ISO> ---` block to the given
error log. The header tag stays English regardless of config.md language.
EOF
      exit 2
      ;;
    *)
      echo "fail-log.sh: unknown subcommand '$1' (try: fail|orchestrator-fail)" >&2
      exit 2
      ;;
  esac
fi
