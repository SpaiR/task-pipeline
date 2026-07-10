#!/usr/bin/env bash
# preamble.sh — Shared header for context-script and helper bash callers.
#
# Provides the four pieces every `*-context.sh` (and a few sibling helpers like
# `close.sh` / `restore.sh`) repeated verbatim:
#   1. `require_config_md`   — hard-stop if `.task/config/config.md` is absent.
#   2. `source_resolve_ws`   — source `_lib/resolve-ws.sh` and run `resolve_ws`.
#   3. `run_validator`       — wrapper over `_lib/../validate/validate.sh`.
#   4. `emit_section` / `emit_file` — output helpers for the `===== title =====`
#                                     section convention every context script uses.
#
# Sourced (NOT exec'd) by callers. The caller MUST bootstrap `$SCRIPT_DIR` to
# point at its OWN directory before sourcing this file, because `BASH_SOURCE`
# inside this file resolves to `_lib/preamble.sh` and is useless for locating
# sibling skill directories (`../validate/validate.sh`, `../_lib/resolve-ws.sh`).
#
# Caller bootstrap (recommended):
#
#   __BOOT="${BASH_SOURCE[0]}"
#   while [ -L "$__BOOT" ]; do
#     D=$(cd "$(dirname "$__BOOT")" && pwd)
#     __BOOT=$(readlink "$__BOOT")
#     [[ "$__BOOT" != /* ]] && __BOOT="$D/$__BOOT"
#   done
#   SCRIPT_DIR=$(cd "$(dirname "$__BOOT")" && pwd)
#   source "$SCRIPT_DIR/../_lib/preamble.sh"
#
# The symlink-resolve loop is intentional — `realpath` is not a built-in on
# macOS, and the pipeline is exercised through plugin install paths where the
# entry script is a symlink in `~/.claude/plugins/.../skills/<name>/<file>.sh`
# pointing at the repo. A naive `dirname "${BASH_SOURCE[0]}"` would land in the
# wrong tree.
#
# This file does NOT set `set -euo pipefail` — that is the caller's
# responsibility (standard bash safety, every caller does it explicitly).

# Resolve AI_DIR up-front via the shared upward walk so every gate below
# (require_config_md, resolve_ws, roadmap helpers) keys off the discovered
# absolute `.task` root — not a cwd-relative `.task` that breaks the moment the
# shell drifts out of the project root. `find_ai_dir` lives in resolve-ws.sh and
# only acts when AI_DIR is unset; sourcing it here is idempotent with the later
# `source_resolve_ws`. SCRIPT_DIR is set by the caller before this file is
# sourced (see the bootstrap contract above).
# shellcheck source=resolve-ws.sh
source "$SCRIPT_DIR/../_lib/resolve-ws.sh"
find_ai_dir

# --- require_config_md ---
# Hard-stop precondition. Exit code 1 with ERROR on stderr if config.md is
# missing. Aligned to stderr across all callers (previously a few printed to
# stdout — see refactor notes).
#
# This is the first gate a freshly created git worktree hits (config.md is
# missing before resolve-ws even runs). When `.task` is absent AND cwd is a
# *linked* worktree, point the user at `/task:bootstrap` join-mode instead of
# the generic message. Guard order keeps git off the happy path: config.md
# present → whole block skipped → no git subprocess. `realpath`/`readlink -f`
# avoided (not built-in on macOS) — compare `cd … && pwd`. The check is
# duplicated (not shared with resolve-ws.sh's `_linked_worktree_without_task`)
# on purpose — bash gates fail closed independently per the repo invariant.
require_config_md() {
  if [[ ! -f "$AI_DIR/config/config.md" ]]; then
    local _gd _common
    if [[ ! -e "$AI_DIR" ]] && command -v git >/dev/null 2>&1 \
       && _gd=$(git rev-parse --git-dir 2>/dev/null) \
       && _gd=$(cd "$_gd" 2>/dev/null && pwd) \
       && _common=$(git rev-parse --git-common-dir 2>/dev/null) \
       && _common=$(cd "$_common" 2>/dev/null && pwd) \
       && [[ "$_gd" != "$_common" ]]; then
      echo "ERROR: you're in a linked git worktree without '.task'. Run /task:bootstrap here to link the shared .task/ from the main worktree." >&2
    else
      echo "ERROR: $AI_DIR/config/config.md not found. Run /task:bootstrap first." >&2
    fi
    exit 1
  fi
}

# --- source_resolve_ws ---
# Source the workspace resolver and run it. Caller must have set SCRIPT_DIR.
# On resolver failure (no .task-current, stale id, missing subfolder), the
# resolver prints to stderr and we exit 1.
source_resolve_ws() {
  # shellcheck source=resolve-ws.sh
  source "$SCRIPT_DIR/../_lib/resolve-ws.sh"
  resolve_ws "$@" || exit 1
}

# --- run_validator <subcmd> [target_file] ---
# Wrapper over the sibling `validate/validate.sh`. Args:
#   $1 — validate.sh subcommand (`task`, `plan`, `roadmap`, ...).
#   $2 — optional target file; if passed and missing, the wrapper returns 0
#        without invoking the validator. This mirrors commit-context.sh's
#        previous behavior (validate task only when task.md exists).
#
# If validate.sh is not executable, returns 0 (mirrors the existing
# `[[ -x "$VALIDATOR" ]] &&` guard each caller had).
# On validation failure, prints ERROR to stderr and exits 1.
run_validator() {
  local subcmd="$1"
  local target_file="${2:-}"
  local VALIDATOR="$SCRIPT_DIR/../validate/validate.sh"

  if [[ ! -x "$VALIDATOR" ]]; then
    return 0
  fi
  if [[ -n "$target_file" && ! -f "$target_file" ]]; then
    return 0
  fi
  if ! bash "$VALIDATOR" "$subcmd" >&2; then
    echo "ERROR: $WS_DIR/$subcmd.md failed format validation. Run \`bash \"\$VALIDATOR\" $subcmd\` to see issues." >&2
    exit 1
  fi
}

# --- set_workspace_root ---
# Used by auto-* context scripts that do NOT call resolve_ws (because at that
# stage no `.task-current` exists — auto-* refuse if it does). Sets WS_DIR to
# the parent of all umbrella subfolders. Distinct semantics from resolve_ws:
# WS_DIR here is `.task/workspace`, not `.task/workspace/<task-id>`.
set_workspace_root() {
  WS_DIR="$AI_DIR/workspace"
}

# --- emit_section <title> ---
emit_section() {
  echo "===== $1 ====="
}

# --- emit_file <path> ---
emit_file() {
  local path="$1"
  if [[ -f "$path" ]]; then
    cat "$path"
  else
    echo "(missing: $path)"
  fi
}
