#!/usr/bin/env bash
# auto-locks.sh — Shared read/write for the orchestrator run lock
# (`.task/roadmap/<slug>.lock`).
#
# Flat `key=value` lines, English keys, parser-stable, written atomically once
# per run by the `/task:auto-roadmap` driver at its Step 2 (launch). This helper
# centralises the two operations the orchestrator used to repeat verbatim:
#
#   read_lock_field <file> <key>          — print value or empty; rc always 0
#   write_lock <path> kv1 kv2 ...         — atomic create via `set -o noclobber`
#
# No in-place update primitive: the lock is intentionally a launch-time
# snapshot — `roadmap_mtime` is refreshed in main-thread memory after every
# successful `/task:ship`, never on disk. If the design ever needs a mutable
# field, add a dedicated primitive then; do not hand-roll sed/awk over the lock.
#
# Dual usage. The file is both source-able (defines functions) and directly
# executable (dispatches on `$1`):
#
#   # As library:
#   source "$SCRIPT_DIR/../_lib/auto-locks.sh"
#   value=$(read_lock_field "$LOCK_FILE" roadmap)
#
#   # As executable (used from SKILL.md bash snippets — keeps prompts short):
#   bash "$CLAUDE_PLUGIN_ROOT/skills/_lib/auto-locks.sh" write .task/roadmap/<slug>.lock \
#     roadmap=.task/roadmap/foo.md \
#     roadmap_mtime=1746810000 \
#     start_item=3 \
#     started=2026-05-14T12:34:56Z \
#     items_filter="$ITEMS_SPEC"          # empty value -> line is skipped
#
# Sourcing this file does NOT set `set -euo pipefail` — that is the caller's
# responsibility. The exec-path entry point sets it explicitly at the bottom.

# --- read_lock_field <file> <key> ---
# Print the value of the first `<key>=` line on stdout. Missing file or
# missing key both print the empty string. Always returns 0 — callers
# distinguish "missing" from "empty" by checking [[ -z "$v" ]] themselves.
read_lock_field() {
  local file=$1
  local key=$2
  [[ -f "$file" ]] || { echo ""; return 0; }
  awk -F= -v k="$key" '$1==k {sub(/^[^=]+=/, ""); print; exit}' "$file"
}

# --- write_lock <path> kv1 kv2 ... ---
# Atomically create `<path>` with one `key=value` line per kv arg. Empty values
# are SKIPPED — that lets callers pass conditional fields like
# `items_filter=$ITEMS_SPEC` without first checking whether `$ITEMS_SPEC` is
# set; an empty value would silently disable include-set semantics downstream
# (read_lock_field returns "" for both missing and empty keys, so the lock
# parser cannot distinguish them — we keep that invariant by never writing
# empty values in the first place).
#
# Atomicity comes from `set -o noclobber` in a subshell: a concurrent caller
# racing past the orchestrator's Step 0 will see EEXIST on `>` and fail,
# instead of half-writing on top of the existing lock. Returns 1 on collision
# (or any other write failure); caller should surface the collision message.
write_lock() {
  local path=$1
  shift
  local kv key value
  # Validate every arg BEFORE creating the file. Truncating first (the old
  # order) left a poison zero-byte lock on a malformed arg: the retry then hit
  # noclobber EEXIST and was misread as "another orchestrator is active",
  # wedging the umbrella permanently.
  for kv in "$@"; do
    if [[ "$kv" != *"="* ]]; then
      echo "ERROR: write_lock arg '$kv' is not key=value" >&2
      return 1
    fi
  done
  (
    set -o noclobber
    : > "$path" || exit 1
    for kv in "$@"; do
      # Split on the FIRST `=` only — values may legitimately contain `=`
      # (e.g. an items_filter spec never has one today, but the contract
      # should not silently corrupt one if it ever does).
      key="${kv%%=*}"
      value="${kv#*=}"
      [[ -z "$value" ]] && continue
      printf '%s=%s\n' "$key" "$value" >> "$path"
    done
  ) 2>/dev/null
}

# ---------------- Exec-path dispatch ----------------
# When run directly (`bash auto-locks.sh <subcmd> ...`), forward to the
# functions above. When sourced, this block is skipped.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail
  case "${1:-}" in
    read)
      shift
      if [[ $# -lt 2 ]]; then
        echo "Usage: auto-locks.sh read <file> <key>" >&2
        exit 2
      fi
      read_lock_field "$@"
      ;;
    write)
      shift
      if [[ $# -lt 1 ]]; then
        echo "Usage: auto-locks.sh write <path> [key=value ...]" >&2
        exit 2
      fi
      write_lock "$@"
      ;;
    ""|-h|--help|help)
      cat >&2 <<'EOF'
Usage:
  auto-locks.sh read   <file> <key>
  auto-locks.sh write  <path> key1=value1 [key2=value2 ...]

Notes:
  - `write` uses `set -o noclobber`; exits 1 on collision.
  - `write` SKIPS args whose value is empty (so optional fields can be
    passed unconditionally as `key=$VAR`).
  - `read` prints empty string for missing file or missing key; rc=0.
EOF
      exit 2
      ;;
    *)
      echo "auto-locks.sh: unknown subcommand '$1' (try: read|write)" >&2
      exit 2
      ;;
  esac
fi
