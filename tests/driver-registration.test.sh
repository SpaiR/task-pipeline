#!/usr/bin/env bash
# Contract under test: the three-way wiring that lets `roadmap-to-workflow` reach
# the shipped driver by name. `.claude-plugin/plugin.json` declares
# `skills/_lib/roadmap-driver.js` under `"workflows"`, which is what makes the
# platform load and register it; the driver's own `meta.name` supplies the second
# half of the registered name; and the skill's Step 2 must invoke exactly
# `<manifest name>:<meta.name>`. Drift in any one of the three kills the launcher
# before its first agent, and no other case file looks at the seam.
#
# What this replaced is why the seam is worth pinning: the skill used to pass a
# `scriptPath` into the plugin, and the Workflow tool permission-checks that path
# against the invoking session's working directory — so it only ever worked from
# a checkout of the plugin itself. Hence the last case.
#
# Text matching only: no jq, and no node (nothing here executes the driver).
source "$(dirname "$0")/lib.sh"

MANIFEST="$T_REPO_ROOT/.claude-plugin/plugin.json"
DRIVER="$T_REPO_ROOT/skills/_lib/roadmap-driver.js"
SKILL="$T_REPO_ROOT/skills/roadmap-to-workflow/SKILL.md"
DRIVER_REL="skills/_lib/roadmap-driver.js"

# Top-level manifest keys sit at exactly two spaces, so this cannot pick up the
# nested `author.name` (four).
manifest_name=$(awk -F'"' '/^  "name":/ {print $4; exit}' "$MANIFEST")
# The `"workflows"` value, whether it stays on one line or gets reflowed, and
# the path it declares exactly as written.
workflows=$(awk '/^  "workflows"/,/\]/' "$MANIFEST")
declared=$(printf '%s\n' "$workflows" | tr ',' '\n' | sed -n 's/.*"\([^"]*\.js\)".*/\1/p' | head -1)
# `meta.name` out of the `export const meta = {` block, either quote style.
meta_name=$(awk '/^export const meta = \{/,/^\}/' "$DRIVER" |
  sed -n -E "s/^  name: ['\"]([^'\"]+)['\"],?[[:space:]]*\$/\1/p")
# Step 2's invocation: the `Workflow({` line through the `args: {` that follows.
call=$(sed -n '/^Workflow({$/,/^  args: {$/p' "$SKILL")
invoked=$(printf '%s\n' "$call" | sed -n -E 's/^  name: "([^"]+)",?[[:space:]]*$/\1/p')

t_case "the manifest declares the driver as a plugin workflow"
# Compared whole, `./` included: the manifest schema requires every declared
# path to start with `./`, and a bare relative path does not just skip the
# driver — the manifest fails validation and the entire plugin refuses to
# load, skills and agent with it.
assert_eq "./$DRIVER_REL" "$declared" "the declared path, ./-prefixed"
[[ -f "$DRIVER" ]] && declared_exists=yes || declared_exists=no
assert_eq "yes" "$declared_exists" "the declared path exists on disk"

t_case "the registered name is composed from the manifest and the driver"
assert_eq "task" "$manifest_name" "manifest name"
assert_eq "roadmap-driver" "$meta_name" "driver meta.name"

t_case "the skill invokes exactly the name those two compose"
# The point of the case: a rename on either side that forgets Step 2 fails here
# rather than at the user's first autopilot run.
assert_eq "$manifest_name:$meta_name" "$invoked" "Step 2 invocation"

t_case "the invocation carries no scriptPath"
# The Forbidden list still names `scriptPath` on purpose, so this looks at the
# call block alone, never the whole file.
assert_eq "0" "$(printf '%s\n' "$call" | grep -c 'scriptPath')" "no scriptPath key"

t_summary
