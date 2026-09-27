#!/usr/bin/env bash
# Contract under test: .claude/hooks/guard-release-files.sh, the repo-local
# PreToolUse hook that .claude/settings.json runs before every Edit, Write and
# MultiEdit. For CHANGELOG.md or .claude-plugin/plugin.json, bare or after a
# "/", it prints one line of hookSpecificOutput JSON with permissionDecision
# "ask" and a reason naming that file; for any other path, and for input with
# no path in it, it prints nothing. Either way it exits 0 and writes nothing to
# stderr: the decision rides on stdout, and only exit 2 would block.
#
# Every input runs twice: with jq on PATH, and on a PATH without it, where the
# hook falls back to sed. The jq pass, and the check that settings.json parses,
# are skipped with a SKIP line when jq is not installed; the sed pass always
# runs.
source "$(dirname "$0")/lib.sh"

HOOK="$T_REPO_ROOT/.claude/hooks/guard-release-files.sh"
SETTINGS="$T_REPO_ROOT/.claude/settings.json"
BASH_BIN=$(command -v bash)

# Everything the sed fallback runs, and no jq. Should the hook ever need another
# tool there, its ask rows fail in the nojq pass rather than pass by luck.
NOJQ=$(t_tmpdir)
for tool in cat tr sed; do
  ln -s "$(command -v "$tool")" "$NOJQ/$tool"
done

MODES="nojq"
if command -v jq >/dev/null 2>&1; then
  MODES="jq nojq"
else
  echo "$T_NAME: SKIP the jq pass and the settings.json parse check — jq is not installed (the sed pass still runs)"
fi

ERRF="$(t_tmpdir)/stderr"
# The documented shape on one line, with a reason that needs no JSON escaping.
ASK_RE='^[{]"hookSpecificOutput":[{]"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"[^"\\]+"[}][}]$'

# verdict <hook> <jq|nojq> <json> → "changelog" or "plugin" for an ask whose
# reason names that file, "none" for silence; anything else says what broke.
verdict() {
  local path_env=$PATH out code
  [[ "$2" == nojq ]] && path_env=$NOJQ
  out=$(printf '%s' "$3" | PATH="$path_env" "$BASH_BIN" "$1" 2>"$ERRF")
  code=$?
  if (( code != 0 )); then echo "exit $code"; return; fi
  if [[ -s "$ERRF" ]]; then echo "stderr: $(cat "$ERRF")"; return; fi
  if [[ -z "$out" ]]; then echo "none"; return; fi
  if ! [[ "$out" =~ $ASK_RE ]]; then echo "not the ask JSON: $out"; return; fi
  case "$out" in
    *CHANGELOG.md*plugin.json* | *plugin.json*CHANGELOG.md*) echo "a reason naming both files" ;;
    *CHANGELOG.md*) echo "changelog" ;;
    *plugin.json*) echo "plugin" ;;
    *) echo "a reason naming neither file" ;;
  esac
}

# expect <want> <label> <json> — one assertion per mode.
expect() {
  local mode
  for mode in $MODES; do
    assert_eq "$1" "$(verdict "$HOOK" "$mode" "$3")" "$2 [$mode]"
  done
}

# A Write call on one line, the way Claude Code sends it.
compact() {
  printf '{"session_id":"test","transcript_path":"/tmp/t.jsonl","cwd":"/work/repo","permission_mode":"auto","hook_event_name":"PreToolUse","tool_name":"Write","tool_input":{"file_path":"%s","content":"# notes\\n"},"tool_use_id":"toolu_test"}' "$1"
}

# An Edit call, pretty-printed across lines.
pretty() {
  cat <<EOF
{
  "session_id": "test",
  "hook_event_name": "PreToolUse",
  "tool_name": "Edit",
  "tool_input": {
    "file_path": "$1",
    "old_string": "a",
    "new_string": "b"
  },
  "tool_use_id": "toolu_test"
}
EOF
}

# <want> <file_path>
ROWS='changelog /work/repo/CHANGELOG.md
changelog CHANGELOG.md
changelog ./CHANGELOG.md
changelog /work/repo/.claude/worktrees/wt/CHANGELOG.md
plugin /work/repo/.claude-plugin/plugin.json
plugin .claude-plugin/plugin.json
plugin ./.claude-plugin/plugin.json
none /work/repo/CHANGELOG.md.bak
none CHANGELOG.md.bak
none /work/repo/website/changelog.md
none website/changelog.md
none /work/repo/NOTCHANGELOG.md
none /work/repo/README.md
none /work/repo/.claude-plugin/marketplace.json
none /work/repo/plugin.json
none /work/repo/x.claude-plugin/plugin.json'

t_case "release files ask, bare or after a slash; every other path is silent"
while read -r want path; do
  expect "$want" "$path, one-line Write" "$(compact "$path")"
  expect "$want" "$path, pretty-printed Edit" "$(pretty "$path")"
done <<<"$ROWS"

t_case "MultiEdit carries its path the same way"
expect changelog "a MultiEdit call" \
  '{"tool_name":"MultiEdit","tool_input":{"file_path":"/work/repo/CHANGELOG.md","edits":[{"old_string":"a","new_string":"b"}]}}'

t_case "only tool_input.file_path counts, never a path quoted in the content"
expect none "another file whose content quotes a release path" \
  '{"tool_name":"Write","tool_input":{"file_path":"/work/repo/notes.md","content":"see {\"file_path\": \"CHANGELOG.md\"}"}}'
expect changelog "a release file whose content, first, quotes another path" \
  '{"tool_name":"Write","tool_input":{"content":"{\"file_path\":\"notes.md\"}","file_path":"/work/repo/CHANGELOG.md"}}'

t_case "JSON escapes in the path are decoded before matching"
expect plugin "escaped slashes" \
  '{"tool_name":"Write","tool_input":{"file_path":"\/work\/repo\/.claude-plugin\/plugin.json","content":""}}'
expect changelog "an escaped quote inside the path" \
  '{"tool_name":"Write","tool_input":{"file_path":"/work/a \"b\"/CHANGELOG.md","content":""}}'

t_case "the key and its value on separate lines"
expect plugin "a line break after the colon" '{
  "tool_name": "Write",
  "tool_input": {
    "file_path":
      "/work/repo/.claude-plugin/plugin.json",
    "content": ""
  }
}'

t_case "no file_path, no decision"
expect none "tool_input without file_path" '{"tool_name":"Write","tool_input":{"content":"x"}}'
expect none "file_path null" '{"tool_name":"Write","tool_input":{"file_path":null}}'
expect none "no tool_input at all" '{"tool_name":"Write"}'
expect none "empty stdin" ''
expect none "stdin that is not JSON" 'not json {'

t_case "the rows can fail: a hook that always asks, or never does, is caught"
# One stub replays a real CHANGELOG.md ask whatever it is sent; the other says
# nothing. Each must disagree with at least one row, or the table has stopped
# covering one of the two outcomes.
stubs=$(t_tmpdir)
cat >"$stubs/always-asks.sh" <<EOF
cat >/dev/null
printf '%s' '{"tool_input":{"file_path":"CHANGELOG.md"}}' | "$BASH_BIN" "$HOOK"
EOF
printf 'cat >/dev/null\n' >"$stubs/never-asks.sh"
for stub in always-asks never-asks; do
  misses=0
  while read -r want path; do
    [[ "$(verdict "$stubs/$stub.sh" nojq "$(compact "$path")")" == "$want" ]] || misses=$((misses + 1))
  done <<<"$ROWS"
  assert_eq "yes" "$( (( misses > 0 )) && echo yes || echo no)" "$stub: at least one row catches it"
done

t_case "settings.json runs this hook on Edit, Write and MultiEdit"
# Claude Code hands a shell-form command to `sh -c` with CLAUDE_PROJECT_DIR
# exported. A wrong path fails nothing on its own: the shell exits 127, a
# non-blocking error, and every edit goes through unguarded. So the command is
# run here exactly that way, not just read, and once more from a project path
# with a space in it, which only a quoted placeholder survives.
if command -v jq >/dev/null 2>&1; then
  jq -e . "$SETTINGS" >/dev/null 2>&1
  assert_exit 0 $? "settings.json parses"
fi
matcher=$(sed -n 's/^[[:space:]]*"matcher": "\([^"]*\)",\{0,1\}$/\1/p' "$SETTINGS")
assert_eq "Edit|Write|MultiEdit" "$matcher" "the one PreToolUse matcher"
cmd=$(sed -n 's/^[[:space:]]*"command": "\(.*\)",\{0,1\}$/\1/p' "$SETTINGS" | sed 's/\\"/"/g')
out=$(compact "$T_REPO_ROOT/CHANGELOG.md" | CLAUDE_PROJECT_DIR="$T_REPO_ROOT" sh -c "$cmd" 2>&1)
assert_contains "$out" '"permissionDecision":"ask"' "run as Claude Code runs it, it asks for CHANGELOG.md"
out=$(compact "$T_REPO_ROOT/README.md" | CLAUDE_PROJECT_DIR="$T_REPO_ROOT" sh -c "$cmd" 2>&1)
assert_eq "" "$out" "and stays silent for README.md"
spaced="$(t_tmpdir)/a project"
mkdir -p "$spaced/.claude/hooks" && cp "$HOOK" "$spaced/.claude/hooks/"
out=$(compact "$spaced/CHANGELOG.md" | CLAUDE_PROJECT_DIR="$spaced" sh -c "$cmd" 2>&1)
assert_contains "$out" '"permissionDecision":"ask"' "from a project path with a space in it"

t_summary
