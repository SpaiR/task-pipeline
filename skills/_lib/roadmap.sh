#!/usr/bin/env bash
# roadmap.sh — Shared roadmap utilities for bash helpers that work with
# `.task/roadmap/*.md`. Source explicitly from the helpers that need it:
#
#   source "$SCRIPT_DIR/../_lib/roadmap.sh"
#
# Not auto-sourced anywhere — source it explicitly from the helpers that need
# it. Today's callers: `validate.sh` and `roadmap-to-workflow`.
#
# Exposed API:
#   resolve_artifact_path <kind> <arg>  — slug-or-path → absolute path under
#                                         $AI_DIR/<kind> (task | roadmap | spec)
#   resolve_roadmap_path <arg>          — thin wrapper: resolve_artifact_path roadmap
#   roadmap_progress_counts <path>      — prints three lines: total / done / unchecked
#
# Conventions:
#   - $AI_DIR is expected to be resolved by the caller via `find_ai_dir`
#     (resolve-ws.sh / validate.sh both run it before sourcing this file). If
#     this file is somehow sourced first, we call find_ai_dir when it is
#     already defined, else fall back to the relative `.task` default.
#   - Task heading shape: `### - [ x~>-] N. <title>`. The 5-state checkbox
#     class is the contract `roadmap-to-workflow`'s driver-side auto-mark and
#     `to-task <slug>#N` item-pick both depend on; do not narrow it to `[ x]` only.

if declare -F find_ai_dir >/dev/null 2>&1; then
  find_ai_dir
else
  : "${AI_DIR:=.task}"
fi

# --- resolve_artifact_path <kind> <arg> ---
# Echoes the resolved artifact path on stdout, or empty string if no match.
# <kind> is the .task subdirectory (task | roadmap | spec). Lookup order:
# explicit path → $AI_DIR/<kind>/<arg> → $AI_DIR/<kind>/<arg>.md.
resolve_artifact_path() {
  local kind="$1" arg="$2"
  if [[ -f "$arg" ]]; then echo "$arg"; return; fi
  if [[ -f "$AI_DIR/$kind/$arg" ]]; then echo "$AI_DIR/$kind/$arg"; return; fi
  if [[ -f "$AI_DIR/$kind/$arg.md" ]]; then echo "$AI_DIR/$kind/$arg.md"; return; fi
  echo ""
}

# --- resolve_roadmap_path <arg> ---
# Thin wrapper over resolve_artifact_path for the roadmap subdir — kept as a
# named entry point because `roadmap-to-workflow` and `validate.sh` call it.
resolve_roadmap_path() { resolve_artifact_path roadmap "$1"; }

# --- roadmap_progress_counts <path> ---
# Emits three lines on stdout:
#   total: <N>
#   done: <N>
#   unchecked: <N>
# DONE counts the same 5-state class the driver's auto-mark treats as "already
# marked" ([x]/[~]/[>]/[-]); without this, a roadmap with [~]/[>]/[-] items
# would report done<total even when no [ ] remains, and the wizard's
# (complete) flag would never fire for it.
roadmap_progress_counts() {
  local file="$1"
  # One pass, three counters — same regex classes as before, one fork not three.
  awk '
    /^### - \[[ x~>-]\] [0-9]+\. / { t++ }
    /^### - \[[x~>-]\] [0-9]+\. /  { d++ }
    /^### - \[ \] [0-9]+\. /       { u++ }
    END { printf "total: %d\ndone: %d\nunchecked: %d\n", t+0, d+0, u+0 }
  ' "$file"
}
