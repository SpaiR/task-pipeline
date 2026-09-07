#!/usr/bin/env bash
# tests/lib.sh — assertion + fixture helpers for the bash-layer test suite.
#
# Sourced by every `tests/*.test.sh`; each case file runs as its own bash
# process (see `tests/run.sh`) and ends with `t_summary`, whose exit status is
# the file's verdict. No bats, no npm — bash, awk and git only, so the suite
# runs on a bare macOS or a CI ubuntu image unchanged.
#
# API:
#   t_case <name>                     — label the checks that follow
#   assert_eq <expected> <actual> [l]  — string equality
#   assert_exit <expected> <actual> [l]— exit-code equality (assert_eq's alias,
#                                        kept separate so failures read right)
#   assert_contains <haystack> <needle> [l]
#   t_tmpdir                          — a registered temp dir, PHYSICAL path
#   make_repo [--config]              — a git repo in a temp dir, PHYSICAL path;
#                                       `--config` also writes .task/CLAUDE.md
#   t_summary                         — print the file's tally, exit 0/1
#
# Paths are physical (`pwd -P`) on purpose: on macOS `mktemp -d` hands back a
# path under the `/var` → `/private/var` symlink, and `resolve-ws.sh` only
# applies its ancestor-walk ceiling when the logical and physical cwd agree.
# A logical temp path would silently exercise the unbounded-walk branch.

# The suite must not inherit the caller's pipeline state: `AI_DIR` short-circuits
# `find_ai_dir` entirely, and `CLAUDE_PROJECT_DIR` is resolution step 4.
unset AI_DIR CLAUDE_PROJECT_DIR

T_REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
T_NAME=$(basename "${0}")
T_CHECKS=0
T_FAILS=0
T_CASE="(no case)"
T_TMPDIRS=()

t_case() { T_CASE="$1"; }

_t_ok() { T_CHECKS=$((T_CHECKS + 1)); }
_t_fail() {
  T_CHECKS=$((T_CHECKS + 1))
  T_FAILS=$((T_FAILS + 1))
  printf 'FAIL %s :: %s\n' "$T_NAME" "$T_CASE"
  printf '%s\n' "$1" | sed 's/^/       /'
}

assert_eq() {
  if [[ "$1" == "$2" ]]; then _t_ok; else
    _t_fail "${3:-assert_eq}
  expected: [$1]
  actual:   [$2]"
  fi
}

assert_exit() { assert_eq "$1" "$2" "${3:-exit code}"; }

assert_contains() {
  if [[ "$1" == *"$2"* ]]; then _t_ok; else
    _t_fail "${3:-assert_contains}
  looked for: [$2]
  in output:
$(printf '%s\n' "$1" | sed 's/^/    | /')"
  fi
}

t_tmpdir() {
  local dir
  dir=$(mktemp -d) || return 1
  dir=$(cd "$dir" && pwd -P)
  T_TMPDIRS+=("$dir")
  printf '%s' "$dir"
}

make_repo() {
  local dir
  dir=$(t_tmpdir) || return 1
  git -C "$dir" init -q
  git -C "$dir" config user.email "test@example.invalid"
  git -C "$dir" config user.name "test"
  if [[ "${1:-}" == "--config" ]]; then
    mkdir -p "$dir/.task"
    printf '# task-pipeline\n\n## Language\n\nEnglish.\n' >"$dir/.task/CLAUDE.md"
  fi
  printf '%s' "$dir"
}

_t_cleanup() {
  local d
  for d in "${T_TMPDIRS[@]:-}"; do
    # Belt and braces before an rm -rf: only ever a non-empty absolute path we
    # created ourselves, never `/` and never a relative fragment.
    [[ -n "$d" && "$d" == /* && "$d" != "/" && -d "$d" ]] && rm -rf "$d"
  done
}
trap _t_cleanup EXIT

t_summary() {
  if (( T_FAILS > 0 )); then
    printf '%s: %d checks, %d FAILED\n' "$T_NAME" "$T_CHECKS" "$T_FAILS"
    exit 1
  fi
  printf '%s: %d checks, all passed\n' "$T_NAME" "$T_CHECKS"
  exit 0
}
