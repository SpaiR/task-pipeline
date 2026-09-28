#!/usr/bin/env bash
# Seeds a repo whose last commit implements add-clamp with a planted defect: above the
# range clamp echoes VALUE, not HIGH, and `sh test.sh` catches it. The eval runner runs
# this in the empty workspace; code-reviewer-uncommitted-fails sources it.
set -eu
git init -q
git config user.name eval && git config user.email eval@example.invalid
mkdir -p .task/task .task/roadmap src
printf '*\n' >.task/.gitignore
printf '## Language\n\nEnglish.\n\n## Build and Tests\n\n`sh test.sh`\n\n## Commit Format\n\nConventional Commits.\n' >.task/CLAUDE.md
printf '# Clamp\n\n### - [ ] 1. Add a clamp helper\n' >.task/roadmap/clamp.md
cat >.task/task/add-clamp.md <<'EOF'
# Add a clamp helper
Roadmap: [clamp](../roadmap/clamp.md)
Source item: #1
---
## Description

`clamp VALUE LOW HIGH` prints VALUE limited to LOW..HIGH.

## Plan

### Step 1: Add clamp and its test
**Goal:** `clamp` prints LOW below the range, HIGH above it, VALUE inside it; `sh test.sh` passes.
**Touches:** `src/clamp.sh` `test.sh`
EOF
echo '# clamp' >README.md
git add README.md && git commit -qm 'chore: initial commit'
cat >src/clamp.sh <<'EOF'
clamp() {
  if [ "$1" -lt "$2" ]; then echo "$2"
  elif [ "$1" -gt "$3" ]; then echo "$1"
  else echo "$1"
  fi
}
EOF
cat >test.sh <<'EOF'
. ./src/clamp.sh
fail=0
check() { got=$(clamp "$1" 0 10); [ "$got" = "$2" ] || { echo "clamp $1 0 10: want $2, got $got"; fail=1; }; }
check -5 0; check 5 5; check 15 10
exit $fail
EOF
git add src/clamp.sh test.sh && git commit -qm 'feat(clamp): add a clamp helper'
