#!/usr/bin/env bash
# Test for touches-gate.sh — focuses on path normalization: an absolute `File:`
# path in plan.md must match the repo-relative path emitted by git diff.
#
# Run: bash skills/_lib/touches-gate.test.sh
# Exit 0 = all pass, 1 = at least one failure. Self-contained (temp git repo).
set -u

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
GATE="$SCRIPT_DIR/touches-gate.sh"

fail=0
pass() { echo "PASS: $1"; }
die()  { echo "FAIL: $1" >&2; fail=1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

cd "$TMP"
git init -q
git config user.email test@example.com
git config user.name test
mkdir -p src
printf 'fn main() {}\n' > src/foo.rs
git add -A
git commit -qm init

# Resolve the repo root the same way touches-gate.sh does, so the absolute path
# we write into plan.md shares the prefix the gate strips (avoids the macOS
# /var -> /private/var symlink mismatch).
REPO=$(git rev-parse --show-toplevel)
ABS="$REPO/src/foo.rs"

cat > plan.md <<EOF
# Plan: normalization test

### Step 1: edit foo
- Goal: tweak foo
- File: $ABS
EOF

# Modify the tracked file so it shows up in git diff --name-only HEAD.
printf '// change\n' >> src/foo.rs

# Case 1: absolute File: must match the relative diff path -> exit 0.
if bash "$GATE" "$TMP/plan.md" 2>/dev/null; then
  pass "absolute File: matches relative git diff path"
else
  die "absolute File: did not match (gate rejected an in-scope file)"
fi

# Case 2: a changed file not covered by the plan must still be rejected.
printf 'x\n' > src/bar.rs
git add src/bar.rs
if bash "$GATE" "$TMP/plan.md" 2>/dev/null; then
  die "out-of-scope file (src/bar.rs) was not rejected"
else
  pass "out-of-scope file rejected"
fi

exit $fail
