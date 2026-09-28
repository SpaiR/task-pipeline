#!/usr/bin/env bash
# write-task.sh — assemble and write `$AI_DIR/task/<slug>.md`.
#
# The one owner of task.md assembly: the header link forms, the `---`
# separator, the section order and the stamped `## Execution` pointer all live
# here, so `to-task` and the driver's plan agent stop hand-building
# the same file three times. See docs/contract.md § task.md format.
#
# Usage:
#   write-task.sh --fresh --slug <slug> --title <title> --description <file>
#                         --plan <file> [--tests <file>]
#                         [--roadmap <slug>] [--item <N>] [--spec <slug>]…
#                         [--force]
#
# `--description` / `--plan` / `--tests` take a file holding the section BODY
# ONLY — no `## Description` / `## Plan` / `## Tests` heading. Every heading is
# emitted here, which is what keeps them parser-stable. Repeat `--spec` once per
# cited spec.
#
# `--fresh` is the one mode: the file is always written whole, never edited in
# place. An existing file is left untouched and the run exits 4 unless
# `--force` is given — the caller's collision guard is what earns the `--force`
# (to-task's overwrite chip; the driver's header match on its own item's file).
#
# Output (two parser-stable lines; the second may span several):
#   WROTE: <abs path> (fresh)
#   VALIDATE: <validate.sh output>
#
# Exit codes:
#   0 written (whatever validate.sh then said — read the VALIDATE lines, the
#     caller decides what a WARN or an ERROR means, as it always has)
#   2 usage error   4 file exists (no --force)
#   5 the write itself failed (unwritable `.task/`, full disk) — nothing was
#     written and no `WROTE:` line is printed, because a caller reports that
#     line as a success and treats only validate exit 2 as fatal.
set -u

SRC="${BASH_SOURCE[0]}"
while [ -L "$SRC" ]; do D=$(cd "$(dirname "$SRC")" && pwd); SRC=$(readlink "$SRC"); [[ "$SRC" != /* ]] && SRC="$D/$SRC"; done
SCRIPT_DIR=$(cd "$(dirname "$SRC")" && pwd)

# The single copy of the pointer every task file carries. Byte-identical
# everywhere by construction: nothing else writes it.
EXECUTION_POINTER='> Read [.task/CLAUDE.md](../CLAUDE.md) and follow its `## Executing a task` section.'

die() { echo "ERROR write-task: $1" >&2; exit "${2:-2}"; }

fresh=0 slug="" title="" roadmap="" item="" desc="" plan="" tests="" force=0
specs=()
while (( $# )); do
  case "$1" in
    --fresh)       fresh=1;          shift ;;
    --slug)        slug="${2:-}";    shift 2 ;;
    --title)       title="${2:-}";   shift 2 ;;
    --roadmap)     roadmap="${2:-}"; shift 2 ;;
    --item)        item="${2:-}";    shift 2 ;;
    --spec)        specs+=("${2:-}"); shift 2 ;;
    --description) desc="${2:-}";    shift 2 ;;
    --plan)        plan="${2:-}";    shift 2 ;;
    --tests)       tests="${2:-}";   shift 2 ;;
    --force)       force=1;          shift ;;
    -h | --help)   sed -n '2,35p' "$SRC" >&2; exit 2 ;;
    *)             die "unknown argument '$1'" ;;
  esac
done

[[ "$fresh" -eq 1 ]] || die "--fresh is required"
[[ -n "$slug" ]]  || die "--slug is required"
[[ "$slug" == */* ]] && die "--slug is a slug, not a path: '$slug'"
[[ -n "$title" ]] || die "--title is required"
[[ -n "$desc" ]]  || die "--description is required"
# Every task file carries a Plan: validate.sh errors on a file without one.
[[ -n "$plan" ]]  || die "--plan is required"
# `-r`, not `-f`: a caller may hand us a process substitution (`<(cat <<'EOF' …)`)
# instead of a temp file, and that is a pipe.
for f in "$desc" "$plan" "$tests"; do
  [[ -z "$f" || -r "$f" ]] || die "cannot read: $f"
done

# shellcheck source=./resolve-ws.sh
source "$SCRIPT_DIR/resolve-ws.sh"     # exports AI_DIR
: "${AI_DIR:?AI_DIR unresolved}"
target="$AI_DIR/task/$slug.md"

# --- body helper: emit a section body with trailing blank lines trimmed ------
emit_body() { # <file>
  LC_ALL=C awk '{ lines[NR] = $0 } END {
    last = NR
    while (last > 0 && lines[last] ~ /^[[:space:]]*$/) last--
    for (i = 1; i <= last; i++) print lines[i]
  }' "$1"
}

if [[ -e "$target" && "$force" -ne 1 ]]; then
  echo "EXISTS: $target — pass --force to overwrite" >&2
  exit 4
fi
mkdir -p "$AI_DIR/task" || die "cannot create $AI_DIR/task" 5
# Stage next to the target, then rename. A redirect straight into `$target`
# truncates it before the first byte lands, so a failed write would leave
# debris there — and, under `--force`, destroy the file it was replacing.
# Every write in the group is checked: only its last one would otherwise
# decide the group's status, and a failed body would still print `WROTE:`.
write_failed() { die "cannot write $target" 5; }
work=$(mktemp "$AI_DIR/task/.$slug.XXXXXX") || write_failed
trap 'rm -f "$work"' EXIT
{
  printf '# %s\n' "$title" || write_failed
  # Cross-artifact references are Markdown links whose LABEL carries the
  # identity; `Source item:` is a number, not a reference, so it stays bare.
  if [[ -n "$roadmap" ]]; then
    printf 'Roadmap: [%s](../roadmap/%s.md)\n' "$roadmap" "$roadmap" || write_failed
  fi
  if [[ -n "$item" ]]; then
    printf 'Source item: #%s\n' "${item#\#}" || write_failed
  fi
  for sp in "${specs[@]:-}"; do
    if [[ -n "$sp" ]]; then
      printf 'Spec: [%s](../spec/%s.md)\n' "$sp" "$sp" || write_failed
    fi
  done
  printf '%s\n' '---' || write_failed
  printf '## Description\n\n' || write_failed
  emit_body "$desc" || write_failed
  printf '\n## Plan\n\n' && emit_body "$plan" || write_failed
  if [[ -n "$tests" ]]; then
    printf '\n## Tests\n\n' && emit_body "$tests" || write_failed
  fi
  printf '\n## Execution\n%s\n' "$EXECUTION_POINTER" || write_failed
} >"$work" || write_failed
mv "$work" "$target" || write_failed

echo "WROTE: $target (fresh)"
echo "VALIDATE:"
bash "$SCRIPT_DIR/../validate/validate.sh" task "$slug" 2>&1 | sed 's/^/  /'
exit 0
