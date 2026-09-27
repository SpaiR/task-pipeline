#!/usr/bin/env bash
# Contract under test: the driver's two display helpers in
# skills/_lib/roadmap-driver.js — itemPhase(), the progress-group title all four
# stages of one item share, and runReport() + digestSummary(), the value the
# invoking skill gets back once any agent has run. runReport's first line is the
# parser-stable headline and must come through untouched. Extracted verbatim
# between their marker comments, as driver-waves.test.sh does for computeWaves.
source "$(dirname "$0")/lib.sh"

DRIVER="$T_REPO_ROOT/skills/_lib/roadmap-driver.js"

if ! command -v node >/dev/null 2>&1; then
  echo "$T_NAME: SKIP — node is not installed"
  exit 0
fi

dir=$(t_tmpdir)
{
  sed -n '/--- itemPhase (pure/,/--- end itemPhase/p' "$DRIVER"
  sed -n '/--- runReport (pure/,/--- end runReport/p' "$DRIVER"
} >"$dir/display.mjs"
for fn in itemPhase digestSummary runReport; do
  if ! grep -q "function $fn" "$dir/display.mjs"; then
    t_case "extract $fn from the driver"
    assert_contains "$(cat "$dir/display.mjs")" "function $fn" "marker comments still present"
    t_summary
  fi
done

# One node run per case keeps a thrown error from masking later assertions.
run_js() { # <js body> → prints result
  { cat "$dir/display.mjs"; printf '%s\n' "$1"; } >"$dir/case.mjs"
  node "$dir/case.mjs" 2>&1
}

t_case "itemPhase keeps a short title whole"
assert_eq "W1 · #3 Config loader" "$(run_js "console.log(itemPhase(1, 3, 'Config loader'))")" "short title"

t_case "itemPhase cuts a long title to 32 characters with an ellipsis"
out=$(run_js "console.log(itemPhase(2, 1, 'Add retry backoff with jitter to the HTTP client layer'))")
assert_eq "W2 · #1 Add retry backoff with jitter t…" "$out" "cut title"
assert_eq "32" "$(run_js "console.log(Array.from(itemPhase(2, 1, 'x'.repeat(80)).replace('W2 · #1 ', '')).length)")" "cut length"

t_case "itemPhase cuts by code point, never inside a character"
assert_eq "W1 · #2 Подключить метрики повторов к д…" \
  "$(run_js "console.log(itemPhase(1, 2, 'Подключить метрики повторов к дашборду сервиса'))")" "Cyrillic"
assert_eq "31" "$(run_js "console.log(Array.from(itemPhase(1, 1, '🚀'.repeat(40)).replace('W1 · #1 ', '')).filter((c) => c === '🚀').length)")" \
  "astral characters are not split into surrogate halves"

t_case "itemPhase collapses whitespace and trims before cutting"
assert_eq "W1 · #4 Split the parser" "$(run_js "console.log(itemPhase(1, 4, '  Split   the\\nparser  '))")" "whitespace"

t_case "digestSummary takes the text after the OK head"
assert_eq "added jittered backoff" \
  "$(run_js "console.log(digestSummary('OK #3 retry-backoff added jittered backoff', 3, 'retry-backoff'))")" "summary"
assert_eq "[]" "$(run_js "console.log('[' + digestSummary('OK #3 retry-backoff', 3, 'retry-backoff') + ']')")" "bare head"

t_case "runReport with nothing landed is the headline alone"
assert_eq "roadmap-to-workflow stopped in wave 1 (planning), item #1: FAIL #1 a b" \
  "$(run_js "console.log(runReport('roadmap-to-workflow stopped in wave 1 (planning), item #1: FAIL #1 a b', []))")" "headline only"

t_case "runReport lists landed items under the headline, in landing order"
out=$(run_js "console.log(runReport('roadmap-to-workflow: all items shipped.', [
  { n: 3, slug: 'config-loader', impl: 'read TOML config', review: 'no findings' },
  { n: 1, slug: 'retry-backoff', impl: '', review: '1 fix, tests green' },
]))")
assert_eq "roadmap-to-workflow: all items shipped.
#3 config-loader — read TOML config; review: no findings
#1 retry-backoff — (no summary); review: 1 fix, tests green" "$out" "report body"

t_summary
