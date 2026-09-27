#!/usr/bin/env bash
# guard-release-files.sh — PreToolUse hook: ask before an edit to a release file.
#
# Repo-local maintainer tooling, wired in .claude/settings.json on the Edit,
# Write and MultiEdit tools; the plugin itself ships no hook. CHANGELOG.md and
# the version in .claude-plugin/plugin.json change only when the user asks
# (CONTRIBUTING.md § When to update CHANGELOG.md, CLAUDE.md § Release
# procedure), so an edit to either file makes Claude Code ask the user first,
# auto mode included. "ask" rather than "deny": a release the user did ask for
# still goes through.
#
# Input:  the PreToolUse JSON on stdin. Only tool_input.file_path is read: with
#         jq when it is installed, with sed when it is not.
# Output: when that path is CHANGELOG.md or .claude-plugin/plugin.json, bare or
#         after a "/" (an absolute path, a worktree's copy), one line of
#         hookSpecificOutput JSON with permissionDecision "ask" and a reason the
#         user sees in the prompt; for any other path, or no path, nothing.
# Exit:   always 0, since the decision rides on stdout. A crash would exit
#         non-zero, which Claude Code treats as a non-blocking error: the guard
#         fails open rather than stopping every edit.
#
# The path is matched as the tool sends it (case-sensitive, not resolved), and
# a Bash write (sed -i, a redirect) never reaches this hook. It is a reminder
# for honest edits, not a sandbox.
set -u

input=$(cat)

if command -v jq >/dev/null 2>&1; then
  path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
else
  # A JSON string holds no raw newline, so joining the lines is safe, and every
  # quote inside a string is escaped, so `"file_path"` followed by a colon can
  # only be the key itself, never text in the content. The capture steps over
  # escaped characters; the second sed decodes the three a path can carry.
  path=$(printf '%s' "$input" | tr '\n' ' ' |
    sed -n -E 's/.*"file_path"[[:space:]]*:[[:space:]]*"(([^"\\]|\\.)*)".*/\1/p' |
    sed -E 's#\\(["\\/])#\1#g')
fi

case "$path" in
  CHANGELOG.md | */CHANGELOG.md)
    reason='CHANGELOG.md is a release file, edited only on an explicit request (CONTRIBUTING.md, When to update CHANGELOG.md). Approve only if you asked for this edit.'
    ;;
  .claude-plugin/plugin.json | */.claude-plugin/plugin.json)
    reason='.claude-plugin/plugin.json holds the plugin version, which changes only in a release you asked for (CLAUDE.md, Release procedure). Approve if this edit leaves the version alone or you asked for a release.'
    ;;
  *)
    exit 0
    ;;
esac

printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"%s"}}\n' "$reason"
