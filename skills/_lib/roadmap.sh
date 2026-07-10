#!/usr/bin/env bash
# roadmap.sh — Shared roadmap utilities for bash helpers that work with
# `.task/roadmap/*.md`. Source explicitly from the helpers that need it:
#
#   source "$SCRIPT_DIR/../_lib/roadmap.sh"
#
# NOT auto-sourced from `preamble.sh` — most context scripts
# (audit/commit/...) never touch roadmaps, and the extra source would
# be wasted I/O on every PreToolUse hook fire and every skill invocation.
# Today's callers: `auto-roadmap-context.sh`, `validate.sh`.
#
# Exposed API:
#   resolve_roadmap_path <arg>       — slug-or-path → absolute path under
#                                      $AI_DIR/roadmap or legacy $AI_DIR/todo
#   roadmap_mtime <path>             — cross-platform stat (BSD %m / GNU %Y)
#   roadmap_progress_counts <path>   — prints three lines: total / done / unchecked
#   list_roadmap_items <path>        — tab-separated `<N>\t<status>\t<title>` per item
#
# Conventions:
#   - $AI_DIR is expected to be resolved by the caller via `find_ai_dir`
#     (preamble.sh / resolve-ws.sh / validate.sh all run it before sourcing this
#     file). If this file is somehow sourced first, we call find_ai_dir when it
#     is already defined, else fall back to the relative `.task` default.
#   - Legacy `.task/todo/<slug>(.md)` fallback is silent by default. Set
#     ROADMAP_WARN_ON_LEGACY=1 in the caller's environment to print a stderr
#     WARN when the legacy path resolves the lookup. `validate.sh` opts in;
#     `auto-roadmap-context.sh` stays silent (the validator it invokes surfaces
#     the same WARN, so a second copy would be noise).
#   - Task heading shape: `### - [ x~>-] N. <title>`. The 5-state checkbox
#     class is the contract close.sh:Step 1.5 and `/task:design --from` auto-pick
#     both depend on; do not narrow it to `[ x]` only.

if declare -F find_ai_dir >/dev/null 2>&1; then
  find_ai_dir
else
  : "${AI_DIR:=.task}"
fi

# --- resolve_roadmap_path <arg> ---
# Echoes the resolved roadmap path on stdout, or empty string if no match.
# Lookup order: explicit path → $AI_DIR/roadmap/<arg>(.md) → legacy
# $AI_DIR/todo/<arg>(.md). The legacy branch optionally prints a WARN on stderr
# when ROADMAP_WARN_ON_LEGACY=1 — preserves validate.sh's deprecation-warning
# UX without re-implementing the function in three places.
resolve_roadmap_path() {
  local arg="$1"
  if [[ -f "$arg" ]]; then echo "$arg"; return; fi
  if [[ -f "$AI_DIR/roadmap/$arg" ]]; then echo "$AI_DIR/roadmap/$arg"; return; fi
  if [[ -f "$AI_DIR/roadmap/$arg.md" ]]; then echo "$AI_DIR/roadmap/$arg.md"; return; fi
  if [[ -f "$AI_DIR/todo/$arg" ]]; then
    if [[ "${ROADMAP_WARN_ON_LEGACY:-0}" == "1" ]]; then
      echo "WARN roadmap($arg): resolved via legacy $AI_DIR/todo/. Rename $AI_DIR/todo/ → $AI_DIR/roadmap/." >&2
    fi
    echo "$AI_DIR/todo/$arg"; return
  fi
  if [[ -f "$AI_DIR/todo/$arg.md" ]]; then
    if [[ "${ROADMAP_WARN_ON_LEGACY:-0}" == "1" ]]; then
      echo "WARN roadmap($arg): resolved via legacy $AI_DIR/todo/. Rename $AI_DIR/todo/ → $AI_DIR/roadmap/." >&2
    fi
    echo "$AI_DIR/todo/$arg.md"; return
  fi
  echo ""
}

# --- roadmap_mtime <path> ---
# Cross-platform file mtime (Unix epoch seconds). Tries BSD `stat -f` first
# (macOS / BSD), falls back to GNU `stat -c` (Linux / busybox), then "0" so
# downstream race checks fail loud rather than silently treating a missing
# stat as a no-op. Name reflects the primary call site (race detection on the
# roadmap file in `auto-roadmap-context.sh`); the underlying stat call works on
# any path. If BOTH stat forms fail on a file that DOES exist (a transient stat
# error, not ENOENT), emit a stderr WARN before the "0" fallback — otherwise a
# spurious "0" could silently suppress a legitimate race detection.
roadmap_mtime() {
  local m
  if m=$(stat -f '%m' "$1" 2>/dev/null || stat -c '%Y' "$1" 2>/dev/null); then
    printf '%s\n' "$m"
    return 0
  fi
  [[ -e "$1" ]] && echo "WARN: stat failed on existing '$1'; treating mtime as 0." >&2
  echo "0"
}

# --- roadmap_progress_counts <path> ---
# Emits three lines on stdout:
#   total: <N>
#   done: <N>
#   unchecked: <N>
# DONE counts the same 5-state class close.sh:Step 1.5 treats as "already
# marked" ([x]/[~]/[>]/[-]); without this, a roadmap with [~]/[>]/[-] items
# would report done<total even when no [ ] remains, and the wizard's
# (complete) flag would never fire for it.
roadmap_progress_counts() {
  local file="$1"
  local total done_n unchecked
  total=$(awk '/^### - \[[ x~>-]\] [0-9]+\. / {n++} END {print n+0}' "$file")
  done_n=$(awk '/^### - \[[x~>-]\] [0-9]+\. / {n++} END {print n+0}' "$file")
  unchecked=$(awk '/^### - \[ \] [0-9]+\. / {n++} END {print n+0}' "$file")
  echo "total: $total"
  echo "done: $done_n"
  echo "unchecked: $unchecked"
}

# --- list_roadmap_items <path> ---
# Emit "N<TAB>status<TAB>title" per roadmap item. Status is one of ` x~>-`
# (literal checkbox char).
list_roadmap_items() {
  local file="$1"
  awk '
    /^### - \[[ x~>-]\] [0-9]+\. / {
      raw = $0
      s = raw; sub(/^### - \[/, "", s); status = substr(s, 1, 1)
      n = raw; sub(/^### - \[[ x~>-]\] /, "", n); sub(/\..*$/, "", n)
      t = raw; sub(/^### - \[[ x~>-]\] [0-9]+\. /, "", t)
      printf "%s\t%s\t%s\n", n, status, t
    }
  ' "$file"
}
