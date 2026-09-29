#!/usr/bin/env bash
# Contract under test: the repo's own cross-references. Prose here cites files,
# headings and steps by name, and a rename breaks those citations without
# failing anything else. This file checks, over every tracked or untracked but
# not ignored Markdown file outside website/ and CHANGELOG.md, skipping fenced
# code, and skipping inline code except where a check says otherwise:
#
#   link     a relative link resolves to a file or directory inside the repo
#   anchor   a link's #anchor matches a GitHub-slugged heading of its target
#   path     a backticked repo path exists: inline code whose first word starts
#            with a top-level directory or is a root file; `:line`, `#anchor`
#            and a trailing / are stripped; text holding < { $ * and .task/
#            paths are skipped; a path git ignores is exempt, since it names
#            output that is never tracked
#   section  a `<file>.md § <Heading>` citation names a heading of that file
#            (backticks, ** and quotes ignored, case-insensitive, one text a
#            word-boundary prefix of the other, a "Name — subtitle" heading
#            also cited as Name; §N and the bare "contract §" shorthand skipped)
#   step     a capitalised `Step N` / `Steps N–M` in a SKILL.md exists as a
#            step heading in that same file (lowercase "step" points elsewhere)
#   coverage every skills/_lib/*.sh, skills/validate/validate.sh and
#            .claude/hooks/*.sh has tests/<name>.test.sh; the driver has at
#            least one tests/driver-*.test.sh
#   rule     every .claude/rules/*.md `paths:` entry is a block-list item, holds
#            no braces, and matches at least one file
#
# bash 3.2 safe; one LC_ALL=C awk pass does the Markdown checks. The awk is
# POSIX (no gawk extensions, no regex intervals) so mawk and BSD awk run it.
source "$(dirname "$0")/lib.sh"

# No exception list: every hit so far was fixed in the prose or named a
# class no check can resolve (placeholders, ignored output), skipped above.
# If an exception ever becomes unavoidable, filter it in the real-tree case
# below, one entry per line, each with its reason.

xref_awk() {
  cat <<'AWK'
function basename_of(p,   k) { k = lastslash(p); return k ? substr(p, k + 1) : p }
function dirname_of(p,   k) { k = lastslash(p); return k ? substr(p, 1, k - 1) : "" }
function lastslash(p,   k, i) {
  k = 0
  for (i = length(p); i > 0; i--) if (substr(p, i, 1) == "/") { k = i; break }
  return k
}
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
function report(check, where, detail) { printf "%s %s: %s\n", check, where, detail }

# Updates the fence state for this line; returns 1 when the line is a fence.
function fence_line(line,   l, ch, n) {
  l = line
  sub(/^[ \t]+/, "", l)
  if (!match(l, /^(```+|~~~+)/)) return 0
  ch = substr(l, 1, 1); n = RLENGTH
  if (!infence) { infence = 1; fch = ch; flen = n; return 1 }
  if (ch == fch && n >= flen && trim(substr(l, n + 1)) == "") { infence = 0; return 1 }
  return 0
}

# Offset of the next backtick run exactly n long in s, or 0.
function find_run(s, n,   off) {
  off = 0
  while (match(s, /`+/)) {
    if (RLENGTH == n) return off + RSTART
    off += RSTART + RLENGTH - 1
    s = substr(s, RSTART + RLENGTH)
  }
  return 0
}

# Splits a line into `prose` (code spans blanked) and code[1..ncode].
function split_code(line,   out, run, n, rest, cl) {
  ncode = 0; out = ""
  while (match(line, /`+/)) {
    run = substr(line, RSTART, RLENGTH); n = RLENGTH
    out = out substr(line, 1, RSTART - 1)
    rest = substr(line, RSTART + n)
    cl = find_run(rest, n)
    if (cl == 0) { out = out run; line = rest; continue }
    ncode++; code[ncode] = substr(rest, 1, cl - 1)
    out = out " "
    line = substr(rest, cl + n)
  }
  prose = out line
}

# Heading text with inline links reduced to their label.
function unlink(s,   out, m, lab) {
  out = ""
  while (match(s, /\[[^]]*\]\([^)]*\)/)) {
    m = substr(s, RSTART, RLENGTH)
    lab = substr(m, 2, index(m, "](") - 2)
    out = out substr(s, 1, RSTART - 1) lab
    s = substr(s, RSTART + RLENGTH)
  }
  return out s
}

function slug(s) {
  s = tolower(unlink(s))
  gsub(/[^a-z0-9 _-]/, "", s)
  gsub(/ /, "-", s)
  return s
}

# Heading or citation text as the section check compares it.
function norm(s) {
  s = unlink(s)
  gsub(/`/, "", s); gsub(/\*\*/, "", s); gsub(/["']/, "", s)
  gsub(/“|”|‘|’/, "", s)
  s = tolower(s)
  gsub(/[ \t]+/, " ", s)
  return trim(s)
}

# a is a prefix of b ending at a word boundary of b.
function wprefix(a, b,   c) {
  if (a == "" || substr(b, 1, length(a)) != a) return 0
  c = substr(b, length(a) + 1, 1)
  return c == "" || c !~ /[a-z0-9]/
}

# Repo-relative path of p resolved against directory d; "\001" when it leaves.
function resolve(d, p,   parts, n, i, stack, top, out) {
  if (substr(p, 1, 1) == "/") { d = ""; p = substr(p, 2) }
  n = split((d == "" ? "" : d "/") p, parts, "/")
  top = 0
  for (i = 1; i <= n; i++) {
    if (parts[i] == "" || parts[i] == ".") continue
    if (parts[i] == "..") { if (top == 0) return "\001"; top--; continue }
    stack[++top] = parts[i]
  }
  out = ""
  for (i = 1; i <= top; i++) out = out (i > 1 ? "/" : "") stack[i]
  return out
}

function exists(p) { return p == "" || (p in files) || (p in dirs) }

function check_link(dest, where,   a, k, p, t) {
  dest = trim(dest)
  if (substr(dest, 1, 1) == "<") { dest = substr(dest, 2); sub(/>.*/, "", dest) }
  else sub(/[ \t].*/, "", dest)
  # A scheme is not a repo link; a <placeholder> destination is a template.
  if (dest == "" || dest ~ /^[A-Za-z][A-Za-z0-9+.-]*:/ || dest ~ /[<{$]/) return
  a = ""; k = index(dest, "#")
  if (k) { a = substr(dest, k + 1); p = substr(dest, 1, k - 1) } else p = dest
  if (p == "") t = FILENAME
  else {
    t = resolve(dirname_of(FILENAME), p)
    if (t == "\001") { report("link", where, dest " leaves the repository"); return }
    if (!exists(t)) { report("link", where, dest " does not resolve"); return }
  }
  if (a != "" && (t in files) && t ~ /\.md$/ && !((t SUBSEP tolower(a)) in anchor))
    report("anchor", where, dest " matches no heading of " t)
}

function check_path(c, where,   tok, orig, first) {
  tok = trim(c)
  sub(/[ \t].*/, "", tok)
  if (tok ~ /[<{$*]/ || tok ~ /^\.task(\/|$)/) return
  orig = tok
  sub(/#.*/, "", tok); sub(/:[0-9].*/, "", tok); sub(/\/+$/, "", tok)
  if (tok == "") return
  first = tok; sub(/\/.*/, "", first)
  if (!(first in top) && !(tok in rootfile)) return
  if (!exists(tok)) report("path?", where, orig)
}

# Resolves a cited file token to a repo path, or "" when none.
function cited_file(tok,   t, b, i, hit, n) {
  sub(/^\$\{[A-Za-z_]+\}\//, "", tok)
  if (tok in files) return tok
  t = resolve(dirname_of(FILENAME), tok)
  if (t != "\001" && (t in files)) return t
  if (index(tok, "/")) return ""
  n = 0
  for (i = 1; i <= nfiles; i++) if (basename_of(filelist[i]) == tok) { hit = filelist[i]; n++ }
  return n == 1 ? hit : ""
}

function check_sections(line, where,   t, i, before, after, ftok, f, cited, q, k, j, ok) {
  t = line
  gsub(/`/, "", t); gsub(/\*\*/, "", t)
  while ((i = index(t, "§")) > 0) {
    before = substr(t, 1, i - 1); after = substr(t, i + length("§")); t = after
    if (!match(before, /[A-Za-z0-9_.\/${}-]+\.md[ \t]*$/)) continue
    ftok = trim(substr(before, RSTART, RLENGTH))
    if (ftok ~ /^\.task\//) continue
    after = trim(after)
    if (after ~ /^[0-9]/ || after == "") continue
    q = substr(after, 1, 1)
    if (q == "\"") { after = substr(after, 2); k = index(after, "\""); if (k) after = substr(after, 1, k - 1) }
    else {
      k = match(after, /§|[][)(|,;:]| (—|–|\+|\/|-) | or | and |\. /)
      if (k) after = substr(after, 1, k - 1)
    }
    cited = norm(after)
    if (cited == "") continue
    f = cited_file(ftok)
    if (f == "") { report("section", where, ftok " § " trim(after) ": no such file"); continue }
    ok = 0
    for (j = 1; j <= hcount[f]; j++)
      if (wprefix(cited, head[f, j]) || wprefix(head[f, j], cited)) { ok = 1; break }
    if (!ok) report("section", where, ftok " § " trim(after) ": no such heading")
  }
}

function check_steps(s, where,   m, pre, lo, hi, id, n, x) {
  while (match(s, /Steps? [0-9]+[A-Za-z]?((–|-)[0-9]+)?/)) {
    pre = RSTART > 1 ? substr(s, RSTART - 1, 1) : ""
    m = substr(s, RSTART, RLENGTH); s = substr(s, RSTART + RLENGTH)
    if (pre ~ /[A-Za-z]/) continue
    # A trailing letter counts only as a whole suffix: "Step 2a", not "Step 2and".
    if (m ~ /[A-Za-z]$/ && substr(s, 1, 1) ~ /[A-Za-z0-9]/) sub(/[A-Za-z]$/, "", m)
    sub(/^Steps? /, "", m)
    if (match(m, /(–|-)/)) { lo = substr(m, 1, RSTART - 1); hi = substr(m, RSTART + RLENGTH) }
    else { lo = m; hi = "" }
    if (hi == "") {
      if (!((FILENAME SUBSEP lo) in step)) report("step", where, "Step " lo " is not a step heading here")
      continue
    }
    for (x = lo + 0; x <= hi + 0; x++)
      if (!((FILENAME SUBSEP x) in step)) report("step", where, "Step " x " is not a step heading here")
  }
}

phase == 1 {
  files[$0] = 1; filelist[++nfiles] = $0
  if (index($0, "/") == 0) rootfile[$0] = 1
  else top[substr($0, 1, index($0, "/") - 1)] = 1
  p = $0
  while ((k = lastslash(p)) > 0) { p = substr(p, 1, k - 1); dirs[p] = 1 }
  next
}

FNR == 1 { infence = 0 }

phase == 2 {
  if (fence_line($0) || infence) next
  if (!match($0, /^#+[ \t]/) || RLENGTH > 7) next
  h = substr($0, RLENGTH + 1)
  sub(/[ \t]+#+[ \t]*$/, "", h); h = trim(h)
  s = slug(h)
  if ((FILENAME SUBSEP s) in anchor) { dup[FILENAME, s]++; s = s "-" dup[FILENAME, s] }
  anchor[FILENAME, s] = 1
  head[FILENAME, ++hcount[FILENAME]] = nh = norm(h)
  # "Name — subtitle" and "Name: subtitle" headings are cited by Name alone.
  if (match(nh, / (—|–) |: /)) head[FILENAME, ++hcount[FILENAME]] = substr(nh, 1, RSTART - 1)
  if (FILENAME ~ /(^|\/)SKILL\.md$/ && match(h, /^Steps? [0-9]+[A-Za-z]?((–|-)[0-9]+)?/)) {
    m = substr(h, RSTART, RLENGTH); sub(/^Steps? /, "", m)
    if (match(m, /(–|-)/)) {
      for (x = substr(m, 1, RSTART - 1) + 0; x <= substr(m, RSTART + RLENGTH) + 0; x++) step[FILENAME, x] = 1
    } else {
      step[FILENAME, m] = 1
      sub(/[A-Za-z]$/, "", m); step[FILENAME, m] = 1
    }
  }
  next
}

phase == 3 {
  if (fence_line($0) || infence) next
  where = FILENAME ":" FNR
  split_code($0)
  s = prose
  while (match(s, /\]\([^)]*\)/)) {
    d = substr(s, RSTART + 2, RLENGTH - 3); s = substr(s, RSTART + RLENGTH)
    check_link(d, where)
  }
  if (match(prose, /^[ \t]*\[[^]]+\]:[ \t]*/)) check_link(substr(prose, RLENGTH + 1), where)
  for (i = 1; i <= ncode; i++) check_path(code[i], where)
  if (index($0, "§")) check_sections($0, where)
  if (FILENAME ~ /(^|\/)SKILL\.md$/) check_steps(prose, where)
  next
}

END {
  driver_tests = 0
  for (i = 1; i <= nfiles; i++) if (filelist[i] ~ /^tests\/driver-[^\/]*\.test\.sh$/) driver_tests++
  for (i = 1; i <= nfiles; i++) {
    f = filelist[i]
    if (f ~ /^skills\/_lib\/[^\/]*\.sh$/ || f == "skills/validate/validate.sh" || f ~ /^\.claude\/hooks\/[^\/]*\.sh$/) {
      t = "tests/" basename_of(f); sub(/\.sh$/, ".test.sh", t)
      if (!(t in files)) report("coverage", f, "no " t)
    }
    if (f == "skills/_lib/roadmap-driver.js" && driver_tests == 0) report("coverage", f, "no tests/driver-*.test.sh")
  }
}
AWK
}

# The paths: entries of one rule file, one "<line> <entry>" per line; an
# inline value comes back as "<line> !inline <value>".
rule_paths() {
  awk '
    NR == 1 { if ($0 != "---") exit; fm = 1; next }
    fm && $0 == "---" { exit }
    !fm { next }
    /^paths:[ \t]*$/ { inpaths = 1; next }
    /^paths:/ { v = $0; sub(/^paths:[ \t]*/, "", v); print NR " !inline " v; next }
    inpaths && /^[ \t]*-[ \t]/ {
      v = $0; sub(/^[ \t]*-[ \t]+/, "", v); sub(/[ \t]+$/, "", v)
      if (v ~ /^".*"$/ || v ~ /^'"'"'.*'"'"'$/) v = substr(v, 2, length(v) - 2)
      print NR " " v; next
    }
    /^[^ \t]/ { inpaths = 0 }
  ' "$1"
}

# xref_scan <root>: one defect per line, "<check> <location>: <detail>".
xref_scan() {
  local root=$1 work list prog md scan f line entry p out
  # Every failure prints a line: an empty result must mean a clean tree.
  work=$(t_tmpdir) || { echo "xref: no temp dir"; return 1; }
  list="$work/paths" prog="$work/xref.awk"
  (cd "$root" && git ls-files -co --exclude-standard) >"$list" 2>/dev/null || { echo "xref: git ls-files failed in $root"; return 1; }
  xref_awk >"$prog"
  md=() scan=()
  while IFS= read -r f; do
    case "$f" in *.md) md+=("$f") ;; *) continue ;; esac
    case "$f" in website/*|CHANGELOG.md) ;; *) scan+=("$f") ;; esac
  done <"$list"
  out=$(cd "$root" && LC_ALL=C awk -f "$prog" phase=1 "$list" phase=2 ${md[@]+"${md[@]}"} phase=3 ${scan[@]+"${scan[@]}"}) ||
    out="${out:+$out
}xref awk: exited non-zero"
  # A missing path git ignores names untracked output (the
  # site build): exempt, not a defect.
  printf '%s\n' "$out" | while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    case "$line" in
      "path? "*)
        p=${line##*: } p=${p%%#*} p=${p%%:[0-9]*}
        git -C "$root" check-ignore -q --no-index -- "$p" </dev/null 2>/dev/null && continue
        printf 'path %s\n' "${line#"path? "}" ;;
      *) printf '%s\n' "$line" ;;
    esac
  done
  while IFS= read -r f; do
    case "$f" in .claude/rules/*.md) ;; *) continue ;; esac
    rule_paths "$root/$f" | while IFS=' ' read -r line entry; do
      case "$entry" in
        '!inline '*) printf 'rule %s:%s: paths: must be a block list, got %s\n' "$f" "$line" "${entry#!inline }"; continue ;;
      esac
      case "$entry" in
        *'{'*|*'}'*) printf 'rule %s:%s: %s holds braces\n' "$f" "$line" "$entry"; continue ;;
      esac
      [[ -n "$(git -C "$root" ls-files -- ":(glob)$entry" </dev/null)" ]] ||
        printf 'rule %s:%s: %s matches no tracked file\n' "$f" "$line" "$entry"
    done
  done <"$list"
}

t_case "a fixture with one planted defect per check reports each of them, and only them"
fx=$(make_repo)
mkdir -p "$fx/docs" "$fx/skills/x" "$fx/skills/_lib" "$fx/skills/validate" "$fx/tests" "$fx/.claude/rules" "$fx/.claude/hooks"
printf 'docs/out/\n*.log\n' >"$fx/.gitignore"
cat >"$fx/docs/a.md" <<'MD'
# Real heading

## Real heading

## Helpers

## Editing protocol — quick rules
MD
cat >"$fx/README.md" <<'MD'
Good: [a](docs/a.md#real-heading), [dup](docs/a.md#real-heading-1), [dir](docs/), [self](#top-title).
# Top title
Bad link: [x](missing.md) and [y](../outside.md).
Bad anchor: [z](docs/a.md#nope).
Paths: `docs/a.md:12` is fine, `docs/gone.md` is not; `docs/<slug>.md`, `.task/x.md` are skipped, the ignored `docs/out/` and `docs/run.log:3` are exempt.
Code: `[w](missing-in-code.md)` is not a link.
Cited: docs/a.md § Helpers is fine, so is docs/a.md § Editing protocol requires it; `docs/a.md` § **Nope**; docs/a.md §3 and contract § Nope are skipped.
Cited file: nowhere.md § Anything.
```
[v](missing-in-fence.md) `docs/gone-in-fence.md`
```
MD
cat >"$fx/skills/x/SKILL.md" <<'MD'
---
name: x
---
### Step 1: Go
### Steps 2–3: Then
Follow Step 1, then Steps 2–3; Step 9 does not exist, the plan's step 9 is elsewhere.
MD
printf 'x\n' >"$fx/skills/_lib/helper.sh"
printf 'x\n' >"$fx/skills/_lib/covered.sh"
printf 'x\n' >"$fx/tests/covered.test.sh"
printf 'x\n' >"$fx/skills/_lib/roadmap-driver.js"
printf 'x\n' >"$fx/skills/validate/validate.sh"
printf 'x\n' >"$fx/.claude/hooks/guard.sh"
cat >"$fx/.claude/rules/r.md" <<'MD'
---
paths:
  - "docs/*.md"
  - "skills/{x,y}/*.md"
  - nothing/**
---
Body.
MD
cat >"$fx/.claude/rules/inline.md" <<'MD'
---
paths: ["docs/*.md"]
---
MD
git -C "$fx" add -A >/dev/null
got=$(xref_scan "$fx" | sort)
assert_contains "$got" "link README.md:3: missing.md does not resolve" "a link to a missing file"
assert_contains "$got" "link README.md:3: ../outside.md leaves the repository" "a link out of the repo"
assert_contains "$got" "anchor README.md:4: docs/a.md#nope matches no heading of docs/a.md" "a dead anchor"
assert_contains "$got" "path README.md:5: docs/gone.md" "a missing backticked path"
assert_contains "$got" "section README.md:7: docs/a.md § Nope: no such heading" "a citation of a missing heading"
assert_contains "$got" "section README.md:8: nowhere.md § Anything.: no such file" "a citation of a missing file"
assert_contains "$got" "step skills/x/SKILL.md:6: Step 9 is not a step heading here" "a missing step"
assert_contains "$got" "coverage skills/_lib/helper.sh: no tests/helper.test.sh" "an untested helper"
assert_contains "$got" "coverage skills/validate/validate.sh: no tests/validate.test.sh" "an untested validate.sh"
assert_contains "$got" "coverage .claude/hooks/guard.sh: no tests/guard.test.sh" "an untested hook"
assert_contains "$got" "coverage skills/_lib/roadmap-driver.js: no tests/driver-*.test.sh" "an untested driver"
assert_contains "$got" "rule .claude/rules/r.md:4: skills/{x,y}/*.md holds braces" "a brace glob"
assert_contains "$got" "rule .claude/rules/r.md:5: nothing/** matches no tracked file" "a glob matching nothing"
assert_contains "$got" "rule .claude/rules/inline.md:2: paths: must be a block list" "an inline paths value"
# Everything else in the fixture is a negative control: good links, the
# duplicate-heading anchor, skipped paths and citations, code and fences,
# lowercase step, the covered helper, the matching glob.
assert_eq "14" "$(printf '%s\n' "$got" | grep -c .)" "exactly the planted defects, nothing else"

t_case "a scan that cannot run says so instead of coming back empty"
assert_contains "$(xref_scan "$(t_tmpdir)")" "xref: git ls-files failed" "a directory that is not a repository"

t_case "the repository's own cross-references all resolve"
got=$(xref_scan "$T_REPO_ROOT")
assert_eq "" "$got" "defects in the real tree"

t_summary
