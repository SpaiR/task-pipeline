#!/usr/bin/env bash
# Contract under test: digestPassed() in skills/_lib/roadmap-driver.js — the
# gate between an item's implement/review digest and the next stage. Only an
# exact `OK #N <item-slug>` head passes; a FAIL, an empty line or a drifted line
# stops the run. Extracted verbatim between its marker comments, as
# driver-waves.test.sh does for computeWaves.
source "$(dirname "$0")/lib.sh"

DRIVER="$T_REPO_ROOT/skills/_lib/roadmap-driver.js"

if ! command -v node >/dev/null 2>&1; then
  echo "$T_NAME: SKIP — node is not installed"
  exit 0
fi

dir=$(t_tmpdir)
sed -n '/--- digestPassed (pure/,/--- end digestPassed/p' "$DRIVER" >"$dir/digest.mjs"
if ! grep -q 'function digestPassed' "$dir/digest.mjs"; then
  t_case "extract digestPassed from the driver"
  assert_contains "$(cat "$dir/digest.mjs")" "function digestPassed" "marker comments still present"
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

t_summary
