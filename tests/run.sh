#!/usr/bin/env bash
# tests/run.sh — run every `tests/*.test.sh` and summarize.
#
# Each case file is a separate bash process, so a crash or an `exit` in one
# cannot take the run down with it. Exit status is 1 if any file failed.
#
#   bash tests/run.sh              # all files
#   bash tests/run.sh validate     # only files whose name contains "validate"
set -u

TESTS_DIR=$(cd "$(dirname "$0")" && pwd)
filter="${1:-}"

files=()
for f in "$TESTS_DIR"/*.test.sh; do
  [[ -f "$f" ]] || continue
  [[ -n "$filter" && "$(basename "$f")" != *"$filter"* ]] && continue
  files+=("$f")
done

if (( ${#files[@]} == 0 )); then
  echo "no test files matched${filter:+ filter '$filter'}" >&2
  exit 1
fi

passed=0
failed=0
failed_names=()
for f in "${files[@]}"; do
  if bash "$f"; then
    passed=$((passed + 1))
  else
    failed=$((failed + 1))
    failed_names+=("$(basename "$f")")
  fi
done

echo "----"
if (( failed > 0 )); then
  echo "FAIL ${#files[@]} file(s): $passed passed, $failed failed — ${failed_names[*]}"
  exit 1
fi
echo "OK ${#files[@]} file(s), all passed"
