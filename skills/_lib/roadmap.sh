#!/usr/bin/env bash
# roadmap.sh — Shared roadmap utilities for bash helpers that work with
# `.task/roadmap/*.md`. Source explicitly from the helpers that need it:
#
#   source "$SCRIPT_DIR/../_lib/roadmap.sh"
#
# Not auto-sourced anywhere. Today's callers: `validate.sh`, `roadmap-items.sh`
# and `preflight.sh` — the last two on `roadmap-to-workflow`'s behalf, which
# sources nothing itself.
#
# Exposed API:
#   resolve_artifact_path <kind> <arg>  — slug (no `/`) or path → path under
#                                         $AI_DIR/<kind> (task | roadmap | spec).
#                                         Callers: validate.sh + roadmap-items.sh.
#   roadmap_progress_counts <path>      — prints two lines: total / done.
#                                         Sole caller: preflight.sh.
#
# Conventions:
#   - $AI_DIR must already be resolved by the caller via `find_ai_dir` before
#     sourcing this file — every caller (validate.sh, preflight.sh,
#     roadmap-items.sh) sources resolve-ws.sh first, which exports AI_DIR. This
#     file does no resolution of its own.
#   - Task heading shape: `### - [ x~>-] N. <title>`. The 5-state checkbox
#     class is the contract `task:code-reviewer`'s auto-mark and
#     `to-task <slug>#N` item-pick both depend on; do not narrow it to `[ x]` only.

# --- resolve_artifact_path <kind> <arg> ---
# Echoes the resolved artifact path on stdout, or empty string if no match.
# <kind> is the .task subdirectory (task | roadmap | spec). An <arg> holding a
# `/` is a path, used as given; anything else is a slug, looked up as
# $AI_DIR/<kind>/<arg> → $AI_DIR/<kind>/<arg>.md and never in the cwd. Checking
# the cwd first let a stray file named like the slug shadow the artifact: the
# items came from it while the reviewer ticked the real roadmap.
resolve_artifact_path() {
  local kind="$1" arg="$2"
  if [[ "$arg" == */* ]]; then
    if [[ -f "$arg" ]]; then echo "$arg"; else echo ""; fi
    return
  fi
  if [[ -f "$AI_DIR/$kind/$arg" ]]; then echo "$AI_DIR/$kind/$arg"; return; fi
  if [[ -f "$AI_DIR/$kind/$arg.md" ]]; then echo "$AI_DIR/$kind/$arg.md"; return; fi
  echo ""
}

# --- roadmap_progress_counts <path> ---
# Emits two lines on stdout:
#   total: <N>
#   done: <N>
# DONE counts the same 5-state class the reviewer's auto-mark treats as "already
# marked" ([x]/[~]/[>]/[-]); without this, a roadmap with [~]/[>]/[-] items
# would report done<total even when no [ ] remains, and the wizard's
# (complete) flag would never fire for it.
#
# Returns awk's status, so a caller can tell an unreadable file from an empty
# one. Byte-wise: in a UTF-8 locale macOS awk aborts on a byte it cannot
# decode, and the counts came back empty; every pattern here is ASCII.
roadmap_progress_counts() {
  local file="$1"
  # One pass, two counters — one fork, not one per counter.
  LC_ALL=C awk '
    /^### - \[[ x~>-]\] [0-9]+\. / { t++ }
    /^### - \[[x~>-]\] [0-9]+\. /  { d++ }
    END { printf "total: %d\ndone: %d\n", t+0, d+0 }
  ' "$file"
}
