#!/usr/bin/env bash
# Contract under test: the roadmap checkbox flip in agents/code-reviewer.md
# phase 7 — the command the reviewer runs once its verdict is OK. Extracted
# verbatim between its `roadmap-flip` marker comments, with only the two value
# lines (`N=`, `ROADMAP=`) substituted, exactly as the agent is told to run it.
source "$(dirname "$0")/lib.sh"

AGENT="$T_REPO_ROOT/agents/code-reviewer.md"

dir=$(t_tmpdir)
sed -n '/<!-- roadmap-flip:start -->/,/<!-- roadmap-flip:end -->/p' "$AGENT" |
  grep -v -e '^<!--' -e '^```' >"$dir/flip.sh"
if ! grep -qx 'N=<item number>' "$dir/flip.sh" || ! grep -qx 'ROADMAP="<absolute roadmap path>"' "$dir/flip.sh"; then
  t_case "extract the flip command from the reviewer"
  assert_contains "$(cat "$dir/flip.sh")" "ROADMAP=" "marker comments and value lines still present"
  t_summary
fi

# flip <n> <roadmap file> → stdout, then the exit code on a last line
flip() {
  sed -e "s|^N=<item number>$|N=$1|" -e "s|^ROADMAP=\"<absolute roadmap path>\"$|ROADMAP=\"$2\"|" "$dir/flip.sh" >"$dir/run.sh"
  bash "$dir/run.sh" 2>&1
  echo "exit=$?"
}

roadmap() { # <file> — a small roadmap with a title carrying a literal `[ ]`
  cat >"$1" <<'EOF'
# Roadmap

### - [ ] 1. First item
### - [x] 2. Already done
### - [ ] 03. Zero-padded item
### - [ ] 4. Handle the [ ] literal in titles
### - [ ] 11. Eleventh item
EOF
}

t_case "an unchecked item is ticked and reports OK"
f="$dir/a.md"; roadmap "$f"
out=$(flip 1 "$f")
assert_contains "$out" "MARK-OK #1" "stdout outcome"
assert_contains "$out" "exit=0" "exit code"
assert_contains "$(cat "$f")" "### - [x] 1. First item" "heading ticked"
assert_contains "$(cat "$f")" "### - [ ] 11. Eleventh item" "#11 untouched by #1"
assert_eq "no" "$([ -e "$f.tmp" ] && echo yes || echo no)" "no temp file left"

t_case "an already-ticked item is a no-op that still reports OK"
f="$dir/b.md"; roadmap "$f"; before=$(cat "$f")
out=$(flip 2 "$f")
assert_contains "$out" "MARK-OK #2" "idempotent success"
assert_eq "$before" "$(cat "$f")" "file unchanged"

t_case "re-running a successful flip stays OK"
f="$dir/c.md"; roadmap "$f"
flip 1 "$f" >/dev/null
out=$(flip 1 "$f")
assert_contains "$out" "MARK-OK #1" "second run"

t_case "a zero-padded heading counts as the same item"
f="$dir/d.md"; roadmap "$f"
out=$(flip 3 "$f")
assert_contains "$out" "MARK-OK #3" "matched 03."
assert_contains "$(cat "$f")" "### - [x] 03. Zero-padded item" "heading ticked"

t_case "a literal [ ] inside the title is left alone"
f="$dir/e.md"; roadmap "$f"
flip 4 "$f" >/dev/null
assert_contains "$(cat "$f")" "### - [x] 4. Handle the [ ] literal in titles" "only the checkbox flipped"

t_case "a pasted #N still ticks the right item and echoes the bare number"
f="$dir/h.md"; roadmap "$f"
out=$(flip "#1" "$f")
assert_contains "$out" "MARK-OK #1" "stdout outcome"
assert_eq "no" "$(grep -q "##1" <<<"$out" && echo yes || echo no)" "no doubled hash"
assert_contains "$(cat "$f")" "### - [x] 1. First item" "heading ticked"

t_case "a path with a space works"
mkdir -p "$dir/with space"; f="$dir/with space/r.md"; roadmap "$f"
out=$(flip 1 "$f")
assert_contains "$out" "MARK-OK #1" "quoted path"

t_case "an item with no heading fails and leaves the file untouched"
f="$dir/f.md"; roadmap "$f"; before=$(cat "$f")
out=$(flip 9 "$f")
assert_contains "$out" "MARK-FAIL #9" "stdout outcome"
assert_contains "$out" "exit=1" "exit code"
assert_eq "$before" "$(cat "$f")" "file unchanged"
assert_eq "no" "$([ -e "$f.tmp" ] && echo yes || echo no)" "temp file removed"

t_case "a duplicated item number fails and leaves the file untouched"
f="$dir/g.md"; roadmap "$f"; printf '### - [ ] 1. Duplicate first\n' >>"$f"; before=$(cat "$f")
out=$(flip 1 "$f")
assert_contains "$out" "MARK-FAIL #1" "stdout outcome"
assert_eq "$before" "$(cat "$f")" "file unchanged"

t_case "a missing roadmap file fails"
out=$(flip 1 "$dir/nope.md")
assert_contains "$out" "MARK-FAIL #1" "stdout outcome"
assert_eq "no" "$([ -e "$dir/nope.md" ] && echo yes || echo no)" "nothing created"

t_summary
