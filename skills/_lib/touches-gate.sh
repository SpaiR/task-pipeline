#!/usr/bin/env bash
# touches-gate.sh — Files-level scope gate for /task:build audit auto-fix.
#
# Reads `File:` and `Touches:` lines from all `### Step N` blocks in plan.md,
# resolves each value (path or symbol) to file(s), then compares
# `git diff --name-only HEAD` against the resulting whitelist.
#
# Usage:
#   bash touches-gate.sh <path-to-plan.md>
#
# Exit codes:
#   0 — diff ⊆ whitelist (all changed files covered by File:/Touches:)
#   1 — diff ⊄ whitelist (one or more files outside scope; listed on stderr)
#   2 — usage error or plan.md not parseable
#
# Whitelist construction:
#   For each step's `File:` value (single path token, one per step):
#     - Add to whitelist if the file exists on disk.
#   For each `Touches:` value (comma-separated tokens):
#     1. If token looks like a path (contains `/` or has known extension)
#        and the file exists — add to whitelist directly.
#     2. Otherwise treat token as a symbol — run `git grep -l -Fw <token>`
#        and add all matching files to whitelist.
#   Whitelist is the union across all File: and Touches: values.
#
# Path normalization:
#   plan.md `File:`/`Touches:` paths may be written absolute
#   (/Users/.../src/foo.rs) while `git diff --name-only HEAD` is always
#   repo-root-relative (src/foo.rs). Both sides are normalized to repo-relative
#   form (strip the `git rev-parse --show-toplevel` prefix) before comparison so
#   an absolute path in the plan still matches the relative diff entry.
#
# Token sanitization (applied to every value before resolution):
#   - Backticks stripped (`Symbol` → Symbol).
#   - Parenthesized descriptions removed ("foo (handles X)" → "foo").
#   - Trailing prose after em-dash (—, U+2014), en-dash (–, U+2013),
#     " -- " (ASCII double dash), or ":" is dropped.
#
# Diagnostic:
#   Tokens that resolve to zero files emit a stderr WARN (one line per token).
#   This surfaces malformed Touches: entries without changing exit semantics —
#   a broken token contributes nothing to the whitelist, which would otherwise
#   look like a clean outside-scope rejection.

set -u

PLAN="${1:?Usage: touches-gate.sh <path-to-plan.md>}"

if [[ ! -f "$PLAN" ]]; then
  echo "ERROR: plan.md not found at $PLAN" >&2
  exit 2
fi

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)

# Normalize a path to repo-root-relative form. plan.md File:/Touches: paths may
# be absolute; git diff --name-only output is always repo-relative. Running both
# sides through this makes an absolute plan path match the relative diff entry.
# A path outside REPO_ROOT (or when not in a git repo) is left untouched.
to_repo_relative() {
  local p=$1
  if [[ -n "$REPO_ROOT" && "$p" == "$REPO_ROOT"/* ]]; then
    p="${p#"$REPO_ROOT"/}"
  fi
  printf '%s' "$p"
}

# --- Step 1: Extract File: and Touches: values from plan.md ---
# Plan format (validate.sh enforces): each `### Step N:` block has `Touches:`
# either inline ("- Touches: sym1, sym2") or as a list ("- Touches:" then
# indented "- sym1" lines). The canonical template (design/phases/blueprint.md)
# also carries `File: <path>` per step — the gate parses it when present so
# decorated `Touches:` symbols can still resolve via the step's File: path.
#
# Parenthesized descriptions are stripped in awk (before comma split) so
# commas inside descriptions do not break inline Touches parsing.
TOUCHES=$(awk '
  /^### Step / { in_step = 1; in_touches_list = 0; next }
  /^### / || /^## / { in_step = 0; in_touches_list = 0; next }

  in_step {
    line = $0
    if (in_touches_list) {
      if (line ~ /^[[:space:]]*$/) next
      if (line ~ /^[[:space:]]+-[[:space:]]+[^[:space:]]/) {
        rest = line
        sub(/^[[:space:]]+-[[:space:]]+/, "", rest)
        gsub(/\([^)]*\)/, "", rest)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", rest)
        if (rest != "") print rest
        next
      } else {
        in_touches_list = 0
      }
    }
    # File: line — emit path directly (single value, no comma split).
    if (match(line, /^[[:space:]]*-?[[:space:]]*File:[[:space:]]*/)) {
      rest = substr(line, RSTART + RLENGTH)
      gsub(/`/, "", rest)
      gsub(/\([^)]*\)/, "", rest)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", rest)
      if (rest != "") print rest
      next
    }
    if (match(line, /^[[:space:]]*-?[[:space:]]*Touches:[[:space:]]*/)) {
      rest = substr(line, RSTART + RLENGTH)
      gsub(/\([^)]*\)/, "", rest)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", rest)
      if (rest != "") {
        # Inline comma-separated form — split and print each.
        n = split(rest, parts, /,/)
        for (i = 1; i <= n; i++) {
          item = parts[i]
          gsub(/^[[:space:]]+|[[:space:]]+$/, "", item)
          if (item != "") print item
        }
        in_touches_list = 0
      } else {
        in_touches_list = 1
      }
    }
  }
' "$PLAN")

if [[ -z "$TOUCHES" ]]; then
  echo "ERROR: no File:/Touches: entries found in $PLAN" >&2
  exit 2
fi

# --- Step 2: Build whitelist ---
WHITELIST=$(mktemp 2>/dev/null || echo "/tmp/touches-gate-wl-$$.txt")
trap 'rm -f "$WHITELIST"' EXIT

while IFS= read -r touch; do
  [[ -z "$touch" ]] && continue
  # Strip backticks if present (Touches may use `Symbol` form).
  touch="${touch//\`/}"
  # Strip trailing description after em-dash (U+2014), en-dash (U+2013),
  # " -- " (ASCII double dash), or ": " (colon + space). Order matters — em-dash
  # first since it is the canonical separator in blueprint.md examples. The colon
  # separator requires a trailing space so a path with a line suffix (src/a.ts:42)
  # is left intact.
  touch="${touch%%—*}"
  touch="${touch%%–*}"
  touch="${touch%% -- *}"
  touch="${touch%%: *}"
  # Trim whitespace.
  touch="$(echo -n "$touch" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
  [[ -z "$touch" ]] && continue

  resolved=0

  # Heuristic: path-like token (contains /) or has a known source extension.
  # The extension set is deliberately broad and language-agnostic — a bare
  # filename in a language not listed here still falls through to the symbol
  # search below, so the only cost of a missing extension is one skipped
  # fast-path, not a wrong result. Keep it a superset of mainstream stacks.
  if [[ "$touch" == */* ]] || [[ "$touch" =~ \.(ts|tsx|mts|cts|js|jsx|mjs|cjs|vue|svelte|astro|py|pyi|go|rs|java|kt|kts|scala|groovy|gradle|clj|cljs|cljc|swift|m|mm|cs|fs|fsx|vb|cpp|cc|cxx|c|h|hpp|hh|hxx|zig|nim|d|rb|php|pl|pm|lua|r|jl|dart|ex|exs|erl|hs|ml|mli|sh|bash|sql|proto|graphql|gql|css|scss|sass|less|html|htm|xml|md|yaml|yml|toml|json|tf|tfvars|ipynb)$ ]]; then
    if [[ -f "$touch" ]]; then
      printf '%s\n' "$(to_repo_relative "$touch")" >> "$WHITELIST"
      continue
    fi
    # If path doesn't exist, fall through to symbol search (maybe the path was
    # informal and the symbol still exists in repo).
  fi

  # Symbol search via git grep.
  matches=$(git grep -l -Fw -- "$touch" 2>/dev/null || true)
  if [[ -n "$matches" ]]; then
    printf '%s\n' "$matches" >> "$WHITELIST"
    resolved=1
  fi

  if [[ $resolved -eq 0 ]]; then
    echo "WARN: token did not resolve to any file (check plan.md File:/Touches:): $touch" >&2
  fi
done <<< "$TOUCHES"

# Dedupe whitelist.
sort -u -o "$WHITELIST" "$WHITELIST"

# --- Step 3: Check diff against whitelist ---
CHANGED=$(git diff --name-only HEAD 2>/dev/null || true)
if [[ -z "$CHANGED" ]]; then
  exit 0  # no diff, trivially in scope
fi

VIOLATING=$(mktemp 2>/dev/null || echo "/tmp/touches-gate-v-$$.txt")
trap 'rm -f "$WHITELIST" "$VIOLATING"' EXIT

while IFS= read -r file; do
  [[ -z "$file" ]] && continue
  # Skip .task/ artifacts — they are pipeline-internal, not subject to Touches.
  # (The active-task pointer lives inside the git dir now, so it never appears
  # in `git diff` and needs no carve-out here.)
  [[ "$file" == .task/* ]] && continue

  if ! grep -qxF -- "$(to_repo_relative "$file")" "$WHITELIST"; then
    echo "$file" >> "$VIOLATING"
  fi
done <<< "$CHANGED"

if [[ -s "$VIOLATING" ]]; then
  echo "ERROR: files changed outside plan.md Touches scope:" >&2
  while IFS= read -r v; do
    echo "  - $v" >&2
  done < "$VIOLATING"
  exit 1
fi

exit 0
