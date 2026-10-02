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

t_case "a Latin-1 README and CONTRIBUTING are read as text, not skipped as binary"
# GNU grep >= 3.5 in a UTF-8 locale treats a file holding an invalid byte as
# binary and suppresses the line, so a Latin-1 README came back `README_LANG:
# none` and a TDD rule on such a line was dropped. The helper pins LC_ALL=C.
# The failure needs a UTF-8 locale and a GNU grep; without either, the case
# still runs but cannot show the regression.
utf8=""
for cand in en_US.UTF-8 C.UTF-8 en_US.utf8 C.utf8; do
  LC_ALL=$cand locale charmap 2>/dev/null | grep -qi 'utf-8' && locale -a 2>/dev/null | grep -qix "$cand" && { utf8=$cand; break; }
done
if [[ -z "$utf8" ]]; then
  echo "detect-project.test.sh: SKIP the UTF-8 locale override — no UTF-8 locale installed; the Latin-1 case runs in the ambient locale" >&2
  utf8=${LC_ALL:-C}
fi
latin=$(t_tmpdir)
printf '# Proyecto\n\nDescripci\363n en espa\361ol.\n' >"$latin/README.md"
printf '# Reglas\n\nEste proyecto es test-driven: escribe la prueba primero (\361).\n' >"$latin/CONTRIBUTING.md"
L_OUT=$(LC_ALL=$utf8 bash "$DETECT" "$latin" 2>&1)
assert_contains "$L_OUT" "README_LANG: non-ascii" "Latin-1 README is non-ascii, not none"
assert_contains "$L_OUT" "TEST_CONVENTION: CONTRIBUTING.md: 3:" "TDD rule on a Latin-1 line is found"
# The awk passes over package.json and Makefile abort on an invalid byte in a
# UTF-8 locale before END prints, which read as `COMMANDS: none`.
printf '# Autor: Jos\351\nall:\n\techo\n' >"$latin/Makefile"
printf '{\n  "description": "Caf\351",\n  "scripts": {\n    "test": "jest"\n  }\n}\n' >"$latin/package.json"
L_OUT=$(LC_ALL=$utf8 bash "$DETECT" "$latin" 2>&1)
assert_contains "$L_OUT" "COMMANDS: Makefile targets: all" "Makefile with a Latin-1 comment still lists its targets"
assert_contains "$L_OUT" "COMMANDS: package.json scripts: test" "package.json with a Latin-1 description still lists its scripts"

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
