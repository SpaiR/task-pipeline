#!/usr/bin/env bash
# audit-context.sh — Gather all context needed by /task:build audit phase in one call.
# Usage: audit-context.sh
#
# Outputs (to stdout) clearly-delimited sections:
#   - config.md
#   - task.md
#   - plan.md
#   - CLAUDE.md (project root, or marker if missing)
#   - iteration: N (next iteration number — derived from `## Iteration N` headings in audit.md)
#   - diff size: file count, line count, trivial flag
#   - diff bundle: filtered list of changed files + per-file `git diff HEAD`
#   - recent history: per-file last 5 commit headlines (`git log -5 --oneline`).
#     Consumed by the Simplicity lens — surfaces churn signals like "defensive
#     check just removed, now being re-added" that look like dead code only
#     against the historical axis. Omitted on initial-commit edge case.
#   - neighborhood map: for each new top-level symbol in the diff, up to 5
#     distinct files in the project where the same name already appears
#     (or "too common" / no entry). Replaces the former Explore subagent.
#
# Diff base: `git diff HEAD` so staged + unstaged changes are both audited
# (falls back to `git diff` if HEAD is missing — initial commit edge case).
#
# Filters applied to the diff bundle to cut noise:
#   - .task/** (pipeline working artifacts)
#   - lock files (package-lock.json, yarn.lock, pnpm-lock.yaml, Cargo.lock,
#     go.sum, Gemfile.lock, Pipfile.lock, poetry.lock, composer.lock,
#     Podfile.lock, pubspec.lock, mix.lock, gradle.lockfile, flake.lock)
#   - snapshots (*.snap, **/__snapshots__/**)
#   - generated dirs (dist/, build/, node_modules/, .next/, target/, vendor/)
#   - binary files (detected via `git diff --numstat` "-\t-\t" rows)

set -euo pipefail

# --- Bootstrap: resolve SCRIPT_DIR through symlinks, then load shared preamble ---
__BOOT="${BASH_SOURCE[0]}"
while [ -L "$__BOOT" ]; do D=$(cd "$(dirname "$__BOOT")" && pwd); __BOOT=$(readlink "$__BOOT"); [[ "$__BOOT" != /* ]] && __BOOT="$D/$__BOOT"; done
SCRIPT_DIR=$(cd "$(dirname "$__BOOT")" && pwd)
# shellcheck source=../_lib/preamble.sh
source "$SCRIPT_DIR/../_lib/preamble.sh"

require_config_md
source_resolve_ws "$@"
run_validator task
run_validator plan

# --- config.md ---
emit_section "config.md"
emit_file "$AI_DIR/config/config.md"
echo

# --- task.md ---
emit_section "task.md"
emit_file "$WS_DIR/task.md"
echo

# --- plan.md ---
emit_section "plan.md"
emit_file "$WS_DIR/plan.md"
echo

# --- CLAUDE.md (project root, optional) ---
# Consumed by the Clarity lens ONLY (per skills/build/phases/audit.md table
# "Per-agent context — kept lean" and Step 2b "Per-call prompt template").
# The orchestrator MUST drop this section from the prompts it builds for the
# Reuse and Simplicity agents; passing CLAUDE.md to them is dead context and
# violates the lensed-context contract. Section header stays `CLAUDE.md` (not
# `CLAUDE.md (clarity-only)`) because audit.md's per-call template forwards
# the section as `--- CLAUDE.md ---` to the Clarity agent verbatim.
emit_section "CLAUDE.md"
if [[ -f "CLAUDE.md" ]]; then
  cat "CLAUDE.md"
else
  echo "(missing)"
fi
echo

# --- iteration number ---
emit_section "iteration"
if [[ -f "$WS_DIR/audit.md" ]]; then
  MAX_N=$(grep -oE '^## Iteration [0-9]+' "$WS_DIR/audit.md" 2>/dev/null | grep -oE '[0-9]+' | sort -n | tail -1 || true)
  ITER=$(( ${MAX_N:-0} + 1 ))
else
  ITER=1
fi
echo "$ITER"
echo

# --- diff base (HEAD if exists, else empty for initial-commit edge case) ---
if git rev-parse --verify HEAD >/dev/null 2>&1; then
  DIFF_BASE="HEAD"
else
  DIFF_BASE=""
fi

# Pathspec excludes — applied to all `git diff` calls below.
# Each lock/snapshot pattern is listed twice: once at any depth (`**/foo`)
# and once at repo root (`foo`), because Git's `**/` prefix does not
# match zero directories.
EXCLUDES=(
  ':(exclude).task/**'
  ':(exclude)package-lock.json'      ':(exclude)**/package-lock.json'
  ':(exclude)yarn.lock'              ':(exclude)**/yarn.lock'
  ':(exclude)pnpm-lock.yaml'         ':(exclude)**/pnpm-lock.yaml'
  ':(exclude)Cargo.lock'             ':(exclude)**/Cargo.lock'
  ':(exclude)go.sum'                 ':(exclude)**/go.sum'
  ':(exclude)Gemfile.lock'           ':(exclude)**/Gemfile.lock'
  ':(exclude)Pipfile.lock'           ':(exclude)**/Pipfile.lock'
  ':(exclude)poetry.lock'            ':(exclude)**/poetry.lock'
  ':(exclude)composer.lock'          ':(exclude)**/composer.lock'
  ':(exclude)Podfile.lock'           ':(exclude)**/Podfile.lock'
  ':(exclude)pubspec.lock'           ':(exclude)**/pubspec.lock'
  ':(exclude)mix.lock'               ':(exclude)**/mix.lock'
  ':(exclude)gradle.lockfile'        ':(exclude)**/gradle.lockfile'
  ':(exclude)flake.lock'             ':(exclude)**/flake.lock'
  ':(exclude)*.snap'                 ':(exclude)**/*.snap'
  ':(exclude)__snapshots__/**'       ':(exclude)**/__snapshots__/**'
  ':(exclude)dist/**'
  ':(exclude)build/**'
  ':(exclude)node_modules/**'
  ':(exclude).next/**'
  ':(exclude)target/**'
  ':(exclude)vendor/**'
)

# Single source-of-truth: numstat over filtered set. Skip binary rows ("-\t-\t...").
NUMSTAT=$(git diff --numstat $DIFF_BASE -- "${EXCLUDES[@]}" 2>/dev/null || true)

FILES=$(echo "$NUMSTAT" | awk -F'\t' 'NF==3 && $1 != "-" { print $3 }')

if [[ -z "$FILES" ]]; then
  FILE_COUNT=0
  LINE_COUNT=0
else
  FILE_COUNT=$(echo "$FILES" | grep -c '^')
  LINE_COUNT=$(echo "$NUMSTAT" | awk -F'\t' 'NF==3 && $1 != "-" { a+=$1; d+=$2 } END { print (a+d)+0 }')
fi

# --- diff size + trivial flag ---
# Trivial threshold: 1 file AND <30 changed lines → main-thread combined audit
# (no subagents). Anything larger goes through the full parallel split.
emit_section "diff size"
echo "files: $FILE_COUNT"
echo "lines_changed: $LINE_COUNT"
if [[ "$FILE_COUNT" == "1" && "$LINE_COUNT" -lt 30 ]]; then
  echo "trivial: true"
else
  echo "trivial: false"
fi
echo

# --- diff bundle ---
emit_section "diff bundle"
if [[ -z "$FILES" ]]; then
  echo "(no changes after filtering lock/snapshot/generated/binary/.task)"
else
  echo "Changed files (after filtering lock/snapshot/generated/binary/.task):"
  echo "$FILES"
  echo
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    echo "----- $f -----"
    git diff $DIFF_BASE -- "$f" || true
    echo
  done <<< "$FILES"
fi
echo

# --- recent history ---
# Consumed by the Simplicity lens ONLY (per skills/build/phases/audit.md table
# "Per-agent context — kept lean" and Step 2b "Per-call prompt template").
# Last 5 commits per changed file — surfaces churn signals like "defensive
# check just removed, now being re-added" that look like dead code only when
# viewed against the historical axis. Cheap by tokens (5 headlines × N files).
# The orchestrator MUST drop this section from the prompts it builds for the
# Reuse and Clarity agents; passing it to them is dead context and violates
# the lensed-context contract.
emit_section "recent history"
if [[ -z "$DIFF_BASE" ]]; then
  # Initial-commit edge case: no HEAD, no history to read.
  echo "(no prior commits)"
elif [[ -z "$FILES" ]]; then
  echo "(no changes)"
else
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    echo "----- $f -----"
    LOG=$(git log -5 --oneline -- "$f" 2>/dev/null || true)
    if [[ -z "$LOG" ]]; then
      echo "(no prior commits)"
    else
      echo "$LOG"
    fi
    echo
  done <<< "$FILES"
fi
echo

# --- neighborhood map ---
# Extracts new top-level symbols from added diff lines and `git grep`s the
# project for each — replaces the former Explore subagent. Only the Reuse lens
# consumes this. May be empty when the diff has no new top-level definitions
# or only modifies existing code; in that case Reuse runs without a map.
emit_section "neighborhood map"
if [[ -z "$FILES" ]]; then
  echo "(no changes)"
else
  # 1. Added lines from the filtered diff (skip "+++" file headers).
  ADDED=$(git diff $DIFF_BASE -- "${EXCLUDES[@]}" 2>/dev/null \
          | grep -E '^\+[^+]' \
          | sed 's/^+//' || true)

  # 2. Symbol extraction — two passes:
  #    (a) keyword-defined declarations at any indent (cross-language)
  #    (b) top-level (indent 0) const/let/var — catches JS/TS arrow funcs and
  #        utility consts; restricted to indent 0 to avoid local-variable noise
  SYMS_KW=$(echo "$ADDED" \
            | grep -oE '\b(function|def|fn|func|fun|class|interface|struct|enum|trait|type|module|mod|impl|protocol)[[:space:]]+[A-Za-z_][A-Za-z0-9_]+' \
            | awk '{print $NF}' || true)
  SYMS_TOP=$(echo "$ADDED" \
             | grep -oE '^(const|let|var)[[:space:]]+[A-Za-z_][A-Za-z0-9_]+' \
             | awk '{print $NF}' || true)

  SYMBOLS=$(printf '%s\n%s\n' "$SYMS_KW" "$SYMS_TOP" \
            | grep -v '^$' \
            | awk '!seen[$0]++' \
            | awk 'length($0) >= 3' \
            | awk 'NR<=50' || true)

  if [[ -z "$SYMBOLS" ]]; then
    echo "(no new top-level symbols detected — Reuse will run without a map)"
  else
    # Build grep excludes: project-wide noise patterns + each changed file.
    GREP_EXCLUDES=("${EXCLUDES[@]}")
    while IFS= read -r f; do
      [[ -n "$f" ]] && GREP_EXCLUDES+=(":(exclude)$f")
    done <<< "$FILES"

    HAS_ANY=0
    while IFS= read -r sym; do
      [[ -z "$sym" ]] && continue

      # Search the working tree (cap raw matches to bound time on hot symbols).
      # Use `-Fw` for portable whole-word match: POSIX ERE has no `\b`, and
      # `-P` (PCRE) is not always compiled into git.
      RAW=$(git grep -n -Fw "$sym" -- "${GREP_EXCLUDES[@]}" 2>/dev/null \
            | awk 'NR<=200' || true)

      [[ -z "$RAW" ]] && continue

      DISTINCT_FILES=$(echo "$RAW" | awk -F: '{print $1}' | awk '!seen[$0]++' | wc -l | tr -d ' ')

      HAS_ANY=1
      echo "- new_symbol: $sym"
      if [[ "$DISTINCT_FILES" -ge 15 ]]; then
        echo "  matches: (too common — ${DISTINCT_FILES}+ files, skipped)"
      else
        echo "  matches:"
        # One representative line per file, up to 5 distinct files.
        DEDUP=$(echo "$RAW" | awk -F: '!seen[$1]++ {print; n++; if (n==5) exit}')
        while IFS= read -r line; do
          [[ -z "$line" ]] && continue
          file=${line%%:*}
          rest=${line#*:}
          lineno=${rest%%:*}
          content=${rest#*:}
          content=$(printf '%s' "$content" | sed 's/^[[:space:]]*//' | cut -c1-100)
          echo "    - $file:$lineno: $content"
        done <<< "$DEDUP"
      fi
    done <<< "$SYMBOLS"

    if [[ "$HAS_ANY" == "0" ]]; then
      echo "(no candidates found for any new symbol — Reuse will run without a map)"
    fi
  fi
fi
