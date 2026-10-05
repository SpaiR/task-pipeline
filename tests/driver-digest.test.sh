#!/usr/bin/env bash
# Contract under test: digestPassed(), flipReported() and flipFailed() in
# skills/_lib/roadmap-driver.js — the gates between an item's implement/review
# digest and the next stage. Only an exact `OK #N <item-slug>` head passes; a
# FAIL, an empty line or a drifted line stops the run. A passing review must
# also carry its phase-7 `MARK-OK #N` line. Extracted verbatim between their
# marker comments, as driver-waves.test.sh does for computeWaves. flipFailed
# recognises the flip's own `MARK-FAIL #N` line, never a free-text digest, and
# deviationsReported collects a resumed implement's whole `DEVIATION #N` lines.
source "$(dirname "$0")/lib.sh"

DRIVER="$T_REPO_ROOT/skills/_lib/roadmap-driver.js"

if ! command -v node >/dev/null 2>&1; then
  echo "$T_NAME: SKIP — node is not installed"
  exit 0
fi

dir=$(t_tmpdir)
sed -n -e '/--- digestPassed (pure/,/--- end digestPassed/p' \
  -e '/--- flipReported (pure/,/--- end flipReported/p' \
  -e '/--- deviationsReported (pure/,/--- end deviationsReported/p' "$DRIVER" >"$dir/digest.mjs"
if ! grep -q 'function digestPassed' "$dir/digest.mjs" || ! grep -q 'function flipReported' "$dir/digest.mjs" ||
  ! grep -q 'function deviationsReported' "$dir/digest.mjs"; then
  t_case "extract digestPassed, flipReported and deviationsReported from the driver"
  assert_contains "$(cat "$dir/digest.mjs")" "function digestPassed" "digestPassed marker comments still present"
  assert_contains "$(cat "$dir/digest.mjs")" "function flipReported" "flipReported marker comments still present"
  assert_contains "$(cat "$dir/digest.mjs")" "function deviationsReported" "deviationsReported marker comments still present"
  t_summary
fi

passes() { # <line> → prints true|false for item #3 retry-backoff
  { cat "$dir/digest.mjs"; printf 'console.log(digestPassed(%s, 3, "retry-backoff"))\n' "$1"; } >"$dir/case.mjs"
  node "$dir/case.mjs" 2>&1
}

t_case "an exact OK head with a summary passes"
assert_eq "true" "$(passes "'OK #3 retry-backoff added jittered backoff'")" "OK + summary"

t_case "an exact OK head without a summary passes"
assert_eq "true" "$(passes "'OK #3 retry-backoff'")" "bare OK head"

t_case "a FAIL line stops"
assert_eq "false" "$(passes "'FAIL #3 retry-backoff tests red'")" "FAIL"

t_case "drifted lines stop instead of reading as passes"
assert_eq "false" "$(passes "'**FAIL** #3 retry-backoff tests red'")" "bolded FAIL"
assert_eq "false" "$(passes "'Review: FAIL #3 retry-backoff'")" "prefixed FAIL"
assert_eq "false" "$(passes "'\`\`\`'")" "closing code fence"
assert_eq "false" "$(passes "'**OK** #3 retry-backoff done'")" "bolded OK"

t_case "an empty or missing line stops"
assert_eq "false" "$(passes "''")" "empty string"
assert_eq "false" "$(passes "undefined")" "undefined"

t_case "the OK head must name this item"
assert_eq "false" "$(passes "'OK #4 retry-backoff done'")" "wrong number"
assert_eq "false" "$(passes "'OK #3 retry-backoff-v2 done'")" "slug prefix is not the slug"
assert_eq "false" "$(passes "'OK #3 other-item done'")" "wrong slug"

flipped() { # <text> → prints true|false for item #3
  { cat "$dir/digest.mjs"; printf 'console.log(flipReported(%s, 3))\n' "$1"; } >"$dir/case.mjs"
  node "$dir/case.mjs" 2>&1
}

t_case "a review report carrying the flip's own line counts as ticked"
assert_eq "true" "$(flipped "'## Review\\nMARK-OK #3\\n\\nOK #3 retry-backoff done'")" "bare line"
assert_eq "true" "$(flipped "'  MARK-OK #3  \\nOK #3 retry-backoff done'")" "indented line"

t_case "a review report without the flip's line does not"
assert_eq "false" "$(flipped "'## Review\\nOK #3 retry-backoff done'")" "phase 7 skipped"
assert_eq "false" "$(flipped "'MARK-FAIL #3\\nFAIL #3 retry-backoff no unique heading'")" "MARK-FAIL"
assert_eq "false" "$(flipped "'MARK-OK #13\\nOK #3 retry-backoff done'")" "another item's number"
assert_eq "false" "$(flipped "'Roadmap: MARK-OK #3 expected\\nOK #3 retry-backoff'")" "mentioned mid-sentence"
assert_eq "false" "$(flipped "undefined")" "undefined"

failed() { # <text> → prints true|false for item #3
  { cat "$dir/digest.mjs"; printf 'console.log(flipFailed(%s, 3))\n' "$1"; } >"$dir/case.mjs"
  node "$dir/case.mjs" 2>&1
}

t_case "only the flip's own MARK-FAIL line counts as a failed flip"
assert_eq "true" "$(failed "'## Review\\nMARK-FAIL #3\\nFAIL #3 retry-backoff roadmap item #3: no unique heading'")" "bare line"
assert_eq "true" "$(failed "'  MARK-FAIL #3  \\nFAIL #3 retry-backoff x'")" "indented line"
assert_eq "false" "$(failed "'FAIL #3 retry-backoff no unique index on users.email'")" "a defect whose text says no unique"
assert_eq "false" "$(failed "'MARK-FAIL #13\\nFAIL #3 retry-backoff x'")" "another item's number"
assert_eq "false" "$(failed "'MARK-OK #3\\nOK #3 retry-backoff done'")" "a successful flip"
assert_eq "false" "$(failed "undefined")" "undefined"

deviations() { # <text> → prints the JSON of deviationsReported(text, 3)
  { cat "$dir/digest.mjs"; printf 'console.log(JSON.stringify(deviationsReported(%s, 3)))\n' "$1"; } >"$dir/case.mjs"
  node "$dir/case.mjs" 2>&1
}

t_case "deviations are collected by whole line and item number only"
assert_eq '["kept the v1 cache key","spec 2 retry cap 5, not 3; invariant 1 holds"]' \
  "$(deviations "'## Notes\\nDEVIATION #3 kept the v1 cache key\\n  DEVIATION #3 spec 2 retry cap 5, not 3; invariant 1 holds  \\nOK #3 retry-backoff done'")" "two lines, trimmed, in order"
assert_eq '[]' "$(deviations "'DEVIATION #13 another item\\nOK #3 retry-backoff done'")" "another item's number"
assert_eq '[]' "$(deviations "'Note: DEVIATION #3 mentioned mid-line\\nOK #3 retry-backoff'")" "an inline mention"
assert_eq '[]' "$(deviations "'**DEVIATION** #3 bolded\\nOK #3 retry-backoff'")" "a bolded marker"
assert_eq '[]' "$(deviations "'DEVIATION #3   \\nOK #3 retry-backoff'")" "a marker with no text"
assert_eq '[]' "$(deviations "undefined")" "undefined"

t_summary
