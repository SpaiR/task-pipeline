#!/usr/bin/env bash
# Contract under test: skills/_lib/preflight.sh — the fixed-shape entry block a
# capture skill's Step 0 is preprocessed with. Shape is the contract: the skills
# branch on these line prefixes, so a reworded line is a broken skill.
source "$(dirname "$0")/lib.sh"

PREFLIGHT="$T_REPO_ROOT/skills/_lib/preflight.sh"

p() { # <dir> <kind> → $P_OUT, $P_EXIT
  local dir="$1" kind="$2"
  P_OUT=$( (cd "$dir" && env -u AI_DIR -u CLAUDE_PROJECT_DIR bash "$PREFLIGHT" "$kind") 2>&1 )
  P_EXIT=$?
}

t_case "an unconfigured project reports CONFIG: absent and still exits 0"
bare=$(make_repo)
p "$bare" capture
assert_exit 0 "$P_EXIT" "no config is not a failure"
assert_contains "$P_OUT" "CONFIG: absent" "config state"
assert_contains "$P_OUT" "ROADMAPS: none" "no roadmaps"
assert_contains "$P_OUT" "TASKS: none" "no tasks"
assert_contains "$P_OUT" "SPECS: none" "no specs"

t_case "a configured project reports its root, roadmap progress and slugs"
repo=$(make_repo --config)
mkdir -p "$repo/.task/roadmap" "$repo/.task/task" "$repo/.task/spec"
cat >"$repo/.task/roadmap/api-v2.md" <<'MD'
# API v2

### 1. Shipped item

- [x] Done

### 2. Open item

- [ ] Done
MD
printf '# T\n' >"$repo/.task/task/some-task.md"
printf '# S\n' >"$repo/.task/spec/event-envelope.md"
p "$repo" capture
assert_exit 0 "$P_EXIT" "configured project"
assert_contains "$P_OUT" "AI_DIR: $repo/.task" "resolved root"
assert_contains "$P_OUT" "PLUGIN_ROOT: $T_REPO_ROOT" "plugin root for the driver args"
assert_contains "$P_OUT" "CONFIG: present" "config state"
assert_contains "$P_OUT" "ROADMAPS: api-v2 1/2 unchecked=2" "progress and open item numbers"
assert_contains "$P_OUT" "TASKS: some-task" "task slugs"
assert_contains "$P_OUT" "SPECS: event-envelope" "spec slugs"

t_case "a fully ticked roadmap reports unchecked=none"
sed 's/^- \[ \] Done$/- [x] Done/' "$repo/.task/roadmap/api-v2.md" >"$repo/.task/roadmap/shipped.md"
p "$repo" capture
assert_contains "$P_OUT" "ROADMAPS: shipped 2/2 unchecked=none" "no open items"

t_case "kind 'workflow' folds in the full validate sweep"
p "$repo" workflow
assert_exit 0 "$P_EXIT" "sweep does not change the exit code"
assert_contains "$P_OUT" "VALIDATE:" "sweep section"
# The seeded roadmap has no `**Ready description:**` blocks, so the sweep must
# report errors — and preflight must still exit 0, leaving the call to the skill.
assert_contains "$P_OUT" "ERROR" "sweep output is passed through"

t_case "a heading with no space after the item dot is not counted as unchecked"
# Same heading grammar `roadmap_progress_counts` (roadmap.sh), roadmap-items.sh
# and validate.sh's item regex all require: `### N. ` (dot THEN space).
# A heading missing that space is not a valid item to any of them, so it must
# not surface here either — else the picker offers an item no other parser sees.
cat >"$repo/.task/roadmap/nospace.md" <<'MD'
# No space

### 3.Title with no space after the dot

- [ ] Done
MD
p "$repo" capture
assert_contains "$P_OUT" "ROADMAPS: nospace 0/0 unchecked=none" "malformed heading counts as zero items, not an open one"

t_case "a well-formed heading with the required space is counted as unchecked"
cat >"$repo/.task/roadmap/withspace.md" <<'MD'
# With space

### 3. Title with the required space

- [ ] Done
MD
p "$repo" capture
assert_contains "$P_OUT" "ROADMAPS: withspace 0/1 unchecked=3" "well-formed heading is offered as open item 3"

t_case "the per-skill kinds task, roadmap and spec are gone — one capture kind replaced them"
for old in task roadmap spec; do
  p "$repo" "$old"
  assert_exit 2 "$P_EXIT" "old kind '$old' is a usage error"
  assert_contains "$P_OUT" "ERROR usage: preflight.sh <capture|workflow>" "usage line names the valid kinds"
done

t_case "kind architecture is gone with to-architecture — a usage error"
p "$repo" architecture
assert_exit 2 "$P_EXIT" "unknown kind"
assert_contains "$P_OUT" "ERROR usage" "usage line names the valid kinds"

t_case "kind plan is gone with to-plan — a usage error, not a silent default"
p "$repo" plan
assert_exit 2 "$P_EXIT" "unknown kind"
assert_contains "$P_OUT" "ERROR usage" "usage line names the valid kinds"

t_case "a configured root missing its .gitignore gets the self-ignoring one back"
fresh=$(make_repo --config)
p "$fresh" capture
assert_exit 0 "$P_EXIT" "restoring is not a failure"
assert_eq "# task-pipeline: keeps .task/ out of git
*" "$(cat "$fresh/.task/.gitignore" 2>/dev/null)" "restored contents"
# The whole point: the folder, the marker itself included, stays out of git.
assert_eq "" "$(git -C "$fresh" status --porcelain --untracked-files=all)" ".task/ invisible to git status"

t_case "an existing .gitignore is the user's and is left byte-for-byte"
owned=$(make_repo --config)
printf 'CLAUDE.md\ntask/\n' >"$owned/.task/.gitignore"
p "$owned" capture
assert_eq "$(printf 'CLAUDE.md\ntask/')" "$(cat "$owned/.task/.gitignore")" "untouched"

t_case "an unconfigured root gets no .gitignore — setup owns first run"
# The folder must exist, or a wrongful write would fail anyway and prove nothing.
mkdir -p "$bare/.task"
p "$bare" capture
assert_contains "$P_OUT" "CONFIG: absent" "still unconfigured"
assert_eq "no" "$([[ -e "$bare/.task/.gitignore" ]] && echo yes || echo no)" "nothing written before setup"

t_case "an unwritable .task/ still prints the block and exits 0"
locked=$(make_repo --config)
chmod a-w "$locked/.task"
if [[ -w "$locked/.task" ]]; then
  # As root a chmod does not bite: the write would succeed and prove nothing.
  echo "$T_NAME: SKIP — .task/ stays writable after chmod (running as root)"
else
  p "$locked" capture
  assert_exit 0 "$P_EXIT" "a failed restore is swallowed"
  assert_contains "$P_OUT" "CONFIG: present" "block still printed"
  assert_eq "no" "$([[ "$P_OUT" == *ermission* ]] && echo yes || echo no)" "no write error leaks into the block"
  assert_eq "no" "$([[ -e "$locked/.task/.gitignore" ]] && echo yes || echo no)" "the write really was refused"
fi
chmod u+w "$locked/.task"

t_case "a byte that is not UTF-8 in a roadmap keeps its progress"
t_utf8_locale
# macOS awk decodes by locale and aborts on an invalid byte: the counts came
# back empty and the open list fell back to `none`, a finished roadmap.
latin=$(make_repo --config)
mkdir -p "$latin/.task/roadmap"
printf '# L\n\n### 1. Caf\351\n\n- [x] Done\n\n### 2. Open\n\n- [ ] Done\n' >"$latin/.task/roadmap/latin1.md"
LC_ALL=$T_UTF8 p "$latin" capture
assert_contains "$P_OUT" "ROADMAPS: latin1 1/2 unchecked=2" "progress survives the byte"

t_case "an unreadable roadmap is never reported as complete"
chmod a-r "$latin/.task/roadmap/latin1.md"
if [[ -r "$latin/.task/roadmap/latin1.md" ]]; then
  echo "$T_NAME: SKIP — the roadmap stays readable after chmod (running as root)"
else
  p "$latin" capture
  assert_exit 0 "$P_EXIT" "block still printed"
  assert_contains "$P_OUT" "ROADMAPS: latin1 ?/? unchecked=unreadable" "a failed read is its own value"
fi
chmod u+r "$latin/.task/roadmap/latin1.md"

t_case "kind workflow prints neither TASKS: nor SPECS:, kind capture prints both"
p "$repo" workflow
assert_eq "0" "$(grep -c '^TASKS:\|^SPECS:' <<<"$P_OUT")" "no unread slug lists for the workflow"
p "$repo" capture
assert_eq "2" "$(grep -c '^TASKS:\|^SPECS:' <<<"$P_OUT")" "the capture skills still get both"

t_case "an unknown kind is a usage error"
p "$repo" nonsense
assert_exit 2 "$P_EXIT" "bad kind"

t_summary
