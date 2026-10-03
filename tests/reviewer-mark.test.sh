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

roadmap() { # <file> — a small roadmap with a title and a body carrying a literal `[ ]`
  cat >"$1" <<'EOF'
# Roadmap

### 1. First item

- [ ] Done

**Dependencies:** —

- [ ] a body checklist line, never the status

### 2. Already done

- [x] Done

### 03. Zero-padded item
- [ ] Done

### 4. Handle the [ ] literal in titles

- [ ] Done

### 5. No status line

**Dependencies:** —

- [ ] a body checklist line, never the status

### 11. Eleventh item

- [ ] Done
EOF
}

# status <n> <file> — the first non-blank line under heading N
status() {
  awk -v n="$1" 'go && NF { print; exit } $0 ~ ("^### 0*" n "\\. ") { go = 1 }' "$2"
}

t_case "an unchecked item is ticked and reports OK"
f="$dir/a.md"; roadmap "$f"; before=$(cat "$f")
out=$(flip 1 "$f")
assert_contains "$out" "MARK-OK #1" "stdout outcome"
assert_contains "$out" "exit=0" "exit code"
assert_eq "- [x] Done" "$(status 1 "$f")" "status line ticked"
assert_eq "- [ ] Done" "$(status 11 "$f")" "#11 untouched by #1"
assert_eq "1" "$(diff <(printf '%s\n' "$before") "$f" | grep -c '^>')" "exactly one line changed"
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
assert_eq "- [x] Done" "$(status 3 "$f")" "status line directly under the heading ticked"

t_case "a literal [ ] inside the title is left alone"
f="$dir/e.md"; roadmap "$f"
flip 4 "$f" >/dev/null
assert_contains "$(cat "$f")" "### 4. Handle the [ ] literal in titles" "heading untouched"
assert_eq "- [x] Done" "$(status 4 "$f")" "only the status line flipped"

t_case "a pasted #N still ticks the right item and echoes the bare number"
f="$dir/h.md"; roadmap "$f"
out=$(flip "#1" "$f")
assert_contains "$out" "MARK-OK #1" "stdout outcome"
assert_eq "no" "$(grep -q "##1" <<<"$out" && echo yes || echo no)" "no doubled hash"
assert_eq "- [x] Done" "$(status 1 "$f")" "status line ticked"

t_case "a heading with no status line fails, and a later checklist line is never ticked"
f="$dir/i.md"; roadmap "$f"; before=$(cat "$f")
out=$(flip 5 "$f")
assert_contains "$out" "MARK-FAIL #5" "stdout outcome"
assert_eq "$before" "$(cat "$f")" "file unchanged"

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
f="$dir/g.md"; roadmap "$f"; printf '\n### 1. Duplicate first\n\n- [ ] Done\n' >>"$f"; before=$(cat "$f")
out=$(flip 1 "$f")
assert_contains "$out" "MARK-FAIL #1" "stdout outcome"
assert_eq "$before" "$(cat "$f")" "file unchanged"

t_case "a byte that is not UTF-8 in an item title still ticks under a UTF-8 locale"
t_utf8_locale
# macOS awk decodes by locale and exits 2 on an invalid byte, which read as a
# missing heading. It trips on a record the heading pattern does not match, so
# the byte sits in another item's title. Every other roadmap parser pins
# LC_ALL=C; so does the flip.
f="$dir/l.md"; roadmap "$f"
printf '\n### 6. Caf\351e item\n\n- [ ] Done\n\n### 7. Seventh item\n\n- [ ] Done\n' >>"$f"
out=$(LC_ALL=$T_UTF8 flip 7 "$f")
assert_contains "$out" "MARK-OK #7" "stdout outcome"
assert_eq "- [x] Done" "$(LC_ALL=C status 7 "$f")" "status line ticked"

t_case "a roadmap in a read-only directory fails and leaves the file untouched"
# The flip stages `$ROADMAP.tmp` beside the roadmap, so an unwritable directory
# fails the write, not the heading check. As root the chmod does not bite.
mkdir -p "$dir/ro"; f="$dir/ro/r.md"; roadmap "$f"; before=$(cat "$f")
chmod a-w "$dir/ro"
if [[ -w "$dir/ro" ]]; then
  echo "$T_NAME: SKIP — the directory stays writable after chmod (running as root)"
else
  out=$(flip 1 "$f")
  assert_contains "$out" "MARK-FAIL #1" "stdout outcome"
  assert_contains "$out" "exit=1" "exit code"
  assert_eq "$before" "$(cat "$f")" "file unchanged"
fi
chmod u+w "$dir/ro"

t_case "a missing roadmap file fails"
out=$(flip 1 "$dir/nope.md")
assert_contains "$out" "MARK-FAIL #1" "stdout outcome"
assert_eq "no" "$([ -e "$dir/nope.md" ] && echo yes || echo no)" "nothing created"

t_summary
