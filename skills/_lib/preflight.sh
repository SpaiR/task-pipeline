#!/usr/bin/env bash
# preflight.sh — print a capture skill's entry state as one parser-stable block.
#
# Usage: bash preflight.sh <task|plan|roadmap|spec|workflow>
#
# Exists so a skill's Step 0 costs zero tool round-trips: the block is
# substituted into the skill body by SKILL.md's `!`-preprocessing, before the
# model reads a word of it. Everything here is deterministic — resolve the root,
# test for the config, list what already exists — so none of it belongs in a
# model's turn.
#
# Output (always these lines, in this order; English and fixed-shape, so a skill
# can branch on them):
#
#   PLUGIN_ROOT: /abs/path/to/the/plugin
#   AI_DIR: /abs/path/.task
#   CONFIG: present | absent
#   ROADMAPS: <slug> <done>/<total> unchecked=<n,n>|none  (one line per roadmap)
#   ROADMAPS: none                                      (when there are none)
#   TASKS: <slug> <slug> … | none
#   SPECS: <slug> <slug> … | none
#   VALIDATE: …                                         (kind `workflow` only)
#
# `unchecked=` lists the ITEM NUMBERS still open, not a count — the pickers in
# `to-task <slug>#N` / `to-plan` / `roadmap-to-workflow` need the numbers.
#
# Exit status is 0 whenever the block was printed, including for an unconfigured
# project: the skill decides what to do from `CONFIG:`, not from an exit code.
# Only a usage error (bad or missing kind) exits 2.
set -u

SRC="${BASH_SOURCE[0]}"
while [ -L "$SRC" ]; do D=$(cd "$(dirname "$SRC")" && pwd); SRC=$(readlink "$SRC"); [[ "$SRC" != /* ]] && SRC="$D/$SRC"; done
SCRIPT_DIR=$(cd "$(dirname "$SRC")" && pwd)

kind="${1:-}"
case "$kind" in
  task | plan | roadmap | spec | workflow) ;;
  *)
    echo "ERROR usage: preflight.sh <task|plan|roadmap|spec|workflow>" >&2
    exit 2
    ;;
esac

# shellcheck source=./resolve-ws.sh
source "$SCRIPT_DIR/resolve-ws.sh"     # sourcing runs find_ai_dir → exports AI_DIR
# shellcheck source=./roadmap.sh
source "$SCRIPT_DIR/roadmap.sh"        # roadmap_progress_counts

# The plugin root is two levels above this script; `roadmap-to-workflow` passes
# it to the Workflow driver, which cannot expand a shell variable itself.
echo "PLUGIN_ROOT: $(cd "$SCRIPT_DIR/../.." && pwd)"
echo "AI_DIR: $AI_DIR"
if [[ -f "$AI_DIR/CLAUDE.md" ]]; then
  echo "CONFIG: present"
else
  echo "CONFIG: absent"
fi

shopt -s nullglob

roadmaps=("$AI_DIR"/roadmap/*.md)
if (( ${#roadmaps[@]} == 0 )); then
  echo "ROADMAPS: none"
else
  for f in "${roadmaps[@]}"; do
    counts=$(roadmap_progress_counts "$f")
    total=$(awk -F': ' '/^total/{print $2}' <<<"$counts")
    done_n=$(awk -F': ' '/^done/{print $2}' <<<"$counts")
    # The item numbers still open. The 5-state checkbox class this keys on is
    # owned by `roadmap.sh` (see its header) — an unchecked item is the one
    # state that is NOT in the done class.
    open=$(awk '
      match($0, /^### - \[ \] [0-9]+\./) {
        s = substr($0, RSTART, RLENGTH); gsub(/[^0-9]/, "", s)
        out = (out == "" ? s : out "," s)
      }
      END { print out }
    ' "$f")
    printf 'ROADMAPS: %s %s/%s unchecked=%s\n' \
      "$(basename "$f" .md)" "$done_n" "$total" "${open:-none}"
  done
fi

# TASKS / SPECS are slug lists: the capture skills use them for the
# slug-collision check and for "is the chat continuing an existing task".
list_slugs() { # <label> <dir>
  local label="$1" dir="$2" f out=""
  for f in "$dir"/*.md; do
    out+=" $(basename "$f" .md)"
  done
  printf '%s:%s\n' "$label" "${out:- none}"
}
list_slugs TASKS "$AI_DIR/task"
list_slugs SPECS "$AI_DIR/spec"

# `roadmap-to-workflow` is the one caller that gates on the whole `.task/` tree
# being well-formed, so it gets the full sweep folded into the same call. Its
# exit code is deliberately swallowed — the skill reads the lines.
if [[ "$kind" == workflow ]]; then
  echo "VALIDATE:"
  bash "$SCRIPT_DIR/../validate/validate.sh" all 2>&1 | sed 's/^/  /'
fi
