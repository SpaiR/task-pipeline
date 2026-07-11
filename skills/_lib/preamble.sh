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
# missing. Aligned to stderr across all callers.
#
# `find_ai_dir` (sourced above) resolves the shared `.task/` root for every
# worktree of a bootstrapped repo — via the `task.root` git-config anchor or the
# git-common-dir fallback — so a freshly created worktree finds config.md with
# no setup. If config.md is genuinely absent (unbootstrapped repo), the generic
# redirect is correct: /task:bootstrap creates it at the shared root.
require_config_md() {
  if [[ ! -f "$AI_DIR/config/config.md" ]]; then
    echo "ERROR: $AI_DIR/config/config.md not found. Run /task:bootstrap first." >&2
    exit 1
  fi
}

# --- source_resolve_ws ---
# Source the workspace resolver and run it. Caller must have set SCRIPT_DIR.
# Migrates a pre-upgrade pointer first (`migrate_legacy_pointer` moves a
# worktree-root `.task-current` into git's per-worktree dir), then self-heals a
# *provably-stale* pointer (empty, or pointing at a missing `workspace/<id>/`
# subfolder): `heal_stale_pointer` removes it with a one-line stderr notice, so
# the following `resolve_ws` reports the clean "no active task" terminal state
# instead of the old "Restore … manually" error. A valid pointer (workspace
# present) is a no-op for the heal, so `close.sh` (which resolves via this
# wrapper against a live umbrella) is unaffected. Both are best-effort — return
# codes intentionally ignored. Only this wrapper and design's open phase
# migrate/heal; the direct sourcers (`validate.sh`, `phase-detect.sh`) call
# `resolve_ws` read-only and never mutate (they read the legacy location as a
# read-only fallback instead). On resolver failure the resolver prints to
# stderr and we exit 1.
source_resolve_ws() {
  # shellcheck source=resolve-ws.sh
  source "$SCRIPT_DIR/../_lib/resolve-ws.sh"
  migrate_legacy_pointer || true
  heal_stale_pointer || true
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
