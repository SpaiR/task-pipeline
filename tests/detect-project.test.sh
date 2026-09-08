#!/usr/bin/env bash
# Contract under test: skills/_lib/detect-project.sh — the facts first-run setup
# picks from. Line prefixes are the contract (setup.md reads them), and the
# command lists are the point: a command that is written down must never be
# guessed.
source "$(dirname "$0")/lib.sh"

DETECT="$T_REPO_ROOT/skills/_lib/detect-project.sh"

d() { # <dir> → $D_OUT, $D_EXIT
  D_OUT=$(bash "$DETECT" "$1" 2>&1)
  D_EXIT=$?
}

t_case "manifests, package.json scripts and Makefile targets are all listed"
proj=$(t_tmpdir)
cat >"$proj/package.json" <<'JSON'
{
  "name": "fixture",
  "scripts": {
    "test": "vitest run",
    "build": "tsc -p ."
  }
}
JSON
cat >"$proj/Makefile" <<'MK'
lint:
	echo lint
test: lint
	echo test
VAR := ignored
.PHONY: lint test
MK
printf '# Contributing\n\nUse conventional commits.\n' >"$proj/CONTRIBUTING.md"
d "$proj"
assert_exit 0 "$D_EXIT" "detection"
assert_contains "$D_OUT" "MANIFEST: package.json Makefile" "manifests"
assert_contains "$D_OUT" "COMMANDS: package.json scripts: test build" "npm scripts"
assert_contains "$D_OUT" "COMMANDS: Makefile targets: lint test" "make targets"
# Paths are relative to ROOT, which the block's first line names.
assert_contains "$D_OUT" "COMMIT_FORMAT_DOC: CONTRIBUTING.md" "commit-format doc"

t_case "a compact scripts block reports its own names, not the next object's"
compact=$(t_tmpdir)
cat >"$compact/package.json" <<'JSON'
{
  "name": "fixture",
  "scripts": { "test": "jest", "build": "tsc" },
  "devDependencies": { "jest": "^29", "typescript": "^5" }
}
JSON
d "$compact"
assert_contains "$D_OUT" "COMMANDS: package.json scripts: test build" "one-line scripts object"
assert_eq "0" "$(grep -c 'typescript' <<<"$D_OUT")" "no dependency names leak in as scripts"

t_case "an empty project reports 'none' on every line rather than omitting it"
empty=$(t_tmpdir)
d "$empty"
assert_exit 0 "$D_EXIT" "empty project"
assert_contains "$D_OUT" "MANIFEST: none" "no manifests"
assert_contains "$D_OUT" "COMMANDS: none" "no commands"
assert_contains "$D_OUT" "COMMIT_FORMAT_DOC: none" "no doc"
assert_contains "$D_OUT" "TEST_CONVENTION: none" "no TDD rule"
assert_contains "$D_OUT" "PROJECT_CLAUDE_MD: absent" "no project config"

t_case "a documented TDD convention is quoted with its file and line"
printf '# Rules\n\nThis project is test-driven: write the test first.\n' >"$empty/CONTRIBUTING.md"
d "$empty"
assert_contains "$D_OUT" "TEST_CONVENTION: CONTRIBUTING.md: 3:" "file and line number"

t_case "prose language is reported as evidence, ascii vs non-ascii"
printf '# Проект\n\nЭто описание на русском языке.\n' >"$empty/README.md"
d "$empty"
assert_contains "$D_OUT" "README_LANG: non-ascii" "non-latin prose"
# The whole line, not just the prefix: verdict, separator and sample. The
# verdict used to go missing while the rest of the line stayed intact, and a
# check that reads only the prefix takes that for success.
assert_eq "README_LANG: non-ascii — Это описание на русском языке." \
  "$(printf '%s\n' "$D_OUT" | grep '^README_LANG:' | sed 's/[[:space:]]*$//')" "the whole line"
printf '# Project\n\nA plain english description.\n' >"$empty/README.md"
d "$empty"
assert_contains "$D_OUT" "README_LANG: ascii" "latin prose"

t_case "the verdict is there on every run, not on most of them"
# It vanished on roughly one run in twenty: `lang_of` fed a here-string to a
# `grep -q` that exits at the first match, and bash 5.x killed the
# command-substitution subshell often enough to fail this file about once per
# twenty suite runs. One call cannot see that — fifty make a recurrence fail
# here instead of somewhere a user is watching.
printf '# Проект\n\nЭто описание на русском языке.\n' >"$empty/README.md"
lost=0
for _ in $(seq 1 50); do
  [[ "$(bash "$DETECT" "$empty" | grep -c '^README_LANG: non-ascii — ')" == 1 ]] || lost=$((lost + 1))
done
assert_eq "0" "$lost" "runs out of 50 that lost the verdict"

t_case "outside a git repository the commit-language line says so"
d "$empty"
assert_contains "$D_OUT" "COMMIT_LANG: none (not a git repository)" "no git"

t_case "a missing directory is a usage error"
d "$empty/nope"
assert_exit 2 "$D_EXIT" "bad argument"

t_summary
