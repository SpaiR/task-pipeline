#!/usr/bin/env bash
# preamble.sh — Shared header for helper bash scripts.
#
# Provides the two pieces every helper needs:
#   1. `require_config`     — hard-stop if `.task/config/config.md` is absent.
#   2. `source_resolve_ws`  — source `_lib/resolve-ws.sh` (exports AI_DIR).
#
# Sourced (NOT exec'd) by callers. The caller MUST bootstrap `$SCRIPT_DIR` to
# point at its OWN directory before sourcing this file, because `BASH_SOURCE`
# inside this file resolves to `_lib/preamble.sh` and is useless for locating
# sibling skill directories (`../_lib/resolve-ws.sh`).
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

# Resolve AI_DIR up-front via the shared upward walk so `require_config` keys
# off the discovered absolute `.task` root — not a cwd-relative `.task` that
# breaks the moment the shell drifts out of the project root. `find_ai_dir`
# lives in resolve-ws.sh and only acts when AI_DIR is unset, so sourcing it
# here is idempotent with the later `source_resolve_ws`. SCRIPT_DIR is set by
# the caller before this file is sourced (see the bootstrap contract above).
# shellcheck source=resolve-ws.sh
source "$SCRIPT_DIR/../_lib/resolve-ws.sh"
find_ai_dir

# --- require_config ---
# Hard-stop precondition. Exit code 1 with ERROR on stderr if config.md is
# missing.
#
# `find_ai_dir` (sourced above) resolves the shared `.task/` root for every
# worktree of a bootstrapped repo — via the `task.root` git-config anchor or
# the git-common-dir fallback — so a freshly created worktree finds config.md
# with no setup. If config.md is genuinely absent (unbootstrapped repo), the
# caller's own `to-*` skill is what runs inline Step 0 setup to create it.
require_config() {
  if [[ ! -f "$AI_DIR/config/config.md" ]]; then
    echo "ERROR: $AI_DIR/config/config.md not found." >&2
    exit 1
  fi
}

# --- source_resolve_ws ---
# Source the root resolver. Caller must have set SCRIPT_DIR. Pure: only
# exports AI_DIR, no pointer, no per-task workspace resolution.
source_resolve_ws() {
  # shellcheck source=resolve-ws.sh
  source "$SCRIPT_DIR/../_lib/resolve-ws.sh"
}
