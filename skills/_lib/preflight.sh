#!/usr/bin/env bash
# preflight.sh — print a capture skill's entry state as one parser-stable block.
#
# Usage: bash preflight.sh <task|roadmap|spec|workflow>
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
#   ROADMAPS: <slug> ?/? unchecked=unreadable           (a roadmap that could not be read)
#   ROADMAPS: none                                      (when there are none)
#   TASKS: <slug> <slug> … | none
#   SPECS: <slug> <slug> … | none
#   VALIDATE: …                                         (kind `workflow` only)
#
# `unchecked=` lists the ITEM NUMBERS still open, not a count — the pickers in
# `to-task <slug>#N` / `roadmap-to-workflow` need the numbers.
#
# Exit status is 0 whenever the block was printed, including for an unconfigured
# project: the skill decides what to do from `CONFIG:`, not from an exit code.
# Only a usage error (bad or missing kind) exits 2.
#
# One side effect, and only on a configured root: a missing `.task/.gitignore`
# (the self-ignoring `*` that keeps `.task/` out of git) is recreated. First-run
# setup writes it; this is the one place every skill but `grill` passes through
# on an existing root, so a deleted marker comes back on the next run instead of
# `.task/` surfacing in `git status`. An existing file is never touched — it is
# the user's — and a failed write is swallowed: the block still prints.
set -u

SRC="${BASH_SOURCE[0]}"
while [ -L "$SRC" ]; do D=$(cd "$(dirname "$SRC")" && pwd); SRC=$(readlink "$SRC"); [[ "$SRC" != /* ]] && SRC="$D/$SRC"; done
SCRIPT_DIR=$(cd "$(dirname "$SRC")" && pwd)

kind="${1:-}"
case "$kind" in
  task | roadmap | spec | workflow) ;;
  *)
    echo "ERROR usage: preflight.sh <task|roadmap|spec|workflow>" >&2
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
  # Absent-only, never a rewrite: `-e` plus `-L` so a user's own non-regular
  # `.gitignore` (a symlink, even a dangling one) also counts as present. The
  # braces matter — a failed `>` reports before a trailing `2>` would apply.
  if [[ ! -e "$AI_DIR/.gitignore" && ! -L "$AI_DIR/.gitignore" ]]; then
    { printf '# task-pipeline: keeps .task/ out of git\n*\n' >"$AI_DIR/.gitignore"; } 2>/dev/null || true
  fi
else
  echo "CONFIG: absent"
fi

shopt -s nullglob

roadmaps=("$AI_DIR"/roadmap/*.md)
if (( ${#roadmaps[@]} == 0 )); then
  echo "ROADMAPS: none"
else
  for f in "${roadmaps[@]}"; do
    # A pass that fails must not print as a finished roadmap: an empty open
    # list falls back to `none`, which the skills read as "every item ticked".
    if ! counts=$(roadmap_progress_counts "$f"); then
      printf 'ROADMAPS: %s ?/? unchecked=unreadable\n' "$(basename "$f" .md)"
      continue
    fi
    # The item numbers still open come from the same pass as the counts, so the
    # heading grammar stays owned by `roadmap.sh`. Parsed with builtins, no fork.
    total="" done_n="" open=""
    while IFS= read -r line; do
      case "$line" in
        "total: "*) total="${line#total: }" ;;
        "done: "*)  done_n="${line#done: }" ;;
        "open:"*)   open="${line#open:}"; open="${open# }" ;;
      esac
    done <<<"$counts"
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
