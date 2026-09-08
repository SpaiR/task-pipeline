#!/usr/bin/env bash
# Contract under test: the `!`-preprocessed commands in a SKILL.md body. The
# platform scans the body before the model ever sees it, runs every injection
# it finds, and aborts the whole skill invocation when one fails — so a
# sentence that merely *shows* the syntax takes the skill down with
# `bash: …: No such file or directory`. Quoting does not help: the pass that
# blanks ordinary code spans exempts a span whose preceding character is a
# backtick or `!`, which is exactly what a double-backtick wrapper produces.
#
# So the rule is positional, not visual: in a skill body, `!` at line start or
# after whitespace followed by a backticked command IS a command. Step 0's
# `preflight.sh` call is the only one any skill is allowed to carry.
source "$(dirname "$0")/lib.sh"

# The body the platform preprocesses — frontmatter is parsed off first.
body() {
  awk 'NR == 1 && $0 == "---" { fm = 1; next } fm && $0 == "---" { fm = 0; next } !fm' "$1"
}

# Live injections in a body, both forms the platform recognizes: the inline
# `!`+backticks one, and a fenced ```! block.
injections() {
  local inline fenced
  inline=$(body "$1" | grep -cE '(^|[[:space:]])!`[^`]+`')
  fenced=$(body "$1" | grep -cE '^```!')
  printf '%s' "$(( inline + fenced ))"
}

t_case "each bash-calling skill carries exactly one injection: its own preflight call"
# The kind argument is checked too — a copy-paste that leaves the wrong one
# behind would hand the skill another skill's entry state.
while read -r skill kind; do
  f="$T_REPO_ROOT/skills/$skill/SKILL.md"
  assert_eq "1" "$(injections "$f")" "$skill: one live injection"
  assert_eq '!`bash "${CLAUDE_PLUGIN_ROOT}/skills/_lib/preflight.sh" '"$kind"'`' \
    "$(body "$f" | grep -oE '(^|[[:space:]])!`[^`]+`' | sed 's/^[[:space:]]*//')" \
    "$skill: and it is the preflight call for kind '$kind'"
done <<'PAIRS'
to-task task
to-plan plan
to-roadmap roadmap
to-spec spec
roadmap-to-workflow workflow
PAIRS

t_case "grill runs no bash at all, so it carries no injection"
assert_eq "0" "$(injections "$T_REPO_ROOT/skills/grill/SKILL.md")" "grill"

t_case "the scan follows the platform's rule, not the eye"
probe="$(t_tmpdir)/SKILL.md"
# Double backticks read as quoting to a human and to a Markdown renderer; the
# platform runs this line. It is the exact shape that broke all five skills.
cat >"$probe" <<'MD'
---
name: probe
---
If that block arrived as a literal `` !`bash …` `` line, run it yourself.
MD
assert_eq "1" "$(injections "$probe")" "a double-backtick wrapper does not quote it"

cat >"$probe" <<'MD'
---
name: probe
---
Run `bash "${CLAUDE_PLUGIN_ROOT}/skills/_lib/preflight.sh" task` yourself.
A `!`-preprocessed command aborts the skill when it fails.
MD
assert_eq "0" "$(injections "$probe")" "an ordinary code span is not a command"

cat >"$probe" <<'MD'
---
name: probe
---
```!
bash "${CLAUDE_PLUGIN_ROOT}/skills/_lib/preflight.sh" task
```
MD
assert_eq "1" "$(injections "$probe")" "the fenced form counts as well"

t_summary
