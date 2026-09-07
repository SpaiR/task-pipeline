#!/usr/bin/env bash
# write-task.sh — assemble and write `$AI_DIR/task/<slug>.md`.
#
# The one owner of task.md assembly: the header link forms, the `---`
# separator, the section order and the stamped `## Execution` pointer all live
# here, so `to-task`, `to-plan` and the driver's plan agent stop hand-building
# the same file three times. See docs/contract.md § task.md format.
#
# Usage:
#   write-task.sh --fresh   --slug <slug> --title <title> --description <file>
#                           [--plan <file>] [--tests <file>]
#                           [--roadmap <slug>] [--item <N>] [--spec <slug>]…
#                           [--force]
#   write-task.sh --promote --slug <slug> --plan <file> [--tests <file>]
#   write-task.sh --revise  --slug <slug> --plan <file> [--tests <file>]
#
# `--description` / `--plan` / `--tests` take a file holding the section BODY
# ONLY — no `## Description` / `## Plan` / `## Tests` heading. Every heading is
# emitted here, which is what keeps them parser-stable. Repeat `--spec` once per
# cited spec.
#
# Modes:
#   --fresh    write the file from scratch. An existing file is left untouched
#              and the run exits 4 unless `--force` is given (the caller's
#              slug-collision guard is what earns the `--force`).
#   --promote  a Description-only file gains `## Plan` (+ `## Tests`), inserted
#              directly above `## Execution`. Header, separator, Description and
#              pointer are not touched.
#   --revise   an existing `## Plan` is replaced in place. `## Tests` is
#              replaced only when `--tests` is passed; otherwise it is left
#              byte-for-byte as it was.
#
# Promote / revise also repair a hand-edited target, because both accept one:
#   - no `## Execution`  → sections are appended and the pointer stamped after
#     them, exactly as a fresh write does;
#   - no `---` separator → one is inserted directly above `## Description`
#     (`validate.sh` treats its absence as a hard ERROR);
#   - no `## Description` → exit 3, file untouched. That is not a task artifact
#     this script can extend, and overwriting it is the caller's decision.
#
# Output (two parser-stable lines; the second may span several):
#   WROTE: <abs path> (fresh|promote|revise)
#   VALIDATE: <validate.sh output>
#
# Exit codes:
#   0 written (whatever validate.sh then said — read the VALIDATE lines, the
#     caller decides what a WARN or an ERROR means, as it always has)
#   2 usage error   3 no `## Description` to extend   4 file exists (no --force)
#   5 the write itself failed (unwritable `.task/`, full disk) — nothing was
#     written and no `WROTE:` line is printed, because a caller reports that
#     line as a success and treats only validate exit 2 as fatal.
set -u

SRC="${BASH_SOURCE[0]}"
while [ -L "$SRC" ]; do D=$(cd "$(dirname "$SRC")" && pwd); SRC=$(readlink "$SRC"); [[ "$SRC" != /* ]] && SRC="$D/$SRC"; done
SCRIPT_DIR=$(cd "$(dirname "$SRC")" && pwd)

# The single copy of the pointer every artifact carries. Byte-identical
# everywhere by construction: nothing else writes it.
EXECUTION_POINTER='> Read [.task/CLAUDE.md](../CLAUDE.md) and follow its `## Executing a task` section.'

die() { echo "ERROR write-task: $1" >&2; exit "${2:-2}"; }

mode="" slug="" title="" roadmap="" item="" desc="" plan="" tests="" force=0
specs=()
while (( $# )); do
  case "$1" in
    --fresh | --promote | --revise) [[ -n "$mode" ]] && die "modes are exclusive: $mode and $1"; mode="${1#--}"; shift ;;
    --slug)        slug="${2:-}";    shift 2 ;;
    --title)       title="${2:-}";   shift 2 ;;
    --roadmap)     roadmap="${2:-}"; shift 2 ;;
    --item)        item="${2:-}";    shift 2 ;;
    --spec)        specs+=("${2:-}"); shift 2 ;;
    --description) desc="${2:-}";    shift 2 ;;
    --plan)        plan="${2:-}";    shift 2 ;;
    --tests)       tests="${2:-}";   shift 2 ;;
    --force)       force=1;          shift ;;
    -h | --help)   sed -n '2,52p' "$SRC" >&2; exit 2 ;;
    *)             die "unknown argument '$1'" ;;
  esac
done

[[ -n "$mode" ]] || die "one of --fresh / --promote / --revise is required"
[[ -n "$slug" ]] || die "--slug is required"
[[ "$slug" == */* ]] && die "--slug is a slug, not a path: '$slug'"
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
  awk '{ lines[NR] = $0 } END {
    last = NR
    while (last > 0 && lines[last] ~ /^[[:space:]]*$/) last--
    for (i = 1; i <= last; i++) print lines[i]
  }' "$1"
}

case "$mode" in
  fresh)
    [[ -n "$title" ]] || die "--fresh requires --title"
    [[ -n "$desc" ]]  || die "--fresh requires --description"
    if [[ -e "$target" && "$force" -ne 1 ]]; then
      echo "EXISTS: $target — pass --force to overwrite" >&2
      exit 4
    fi
    mkdir -p "$AI_DIR/task" || die "cannot create $AI_DIR/task" 5
    {
      printf '# %s\n' "$title"
      # Cross-artifact references are Markdown links whose LABEL carries the
      # identity; `Source item:` is a number, not a reference, so it stays bare.
      [[ -n "$roadmap" ]] && printf 'Roadmap: [%s](../roadmap/%s.md)\n' "$roadmap" "$roadmap"
      [[ -n "$item" ]]    && printf 'Source item: #%s\n' "${item#\#}"
      for sp in "${specs[@]:-}"; do
        [[ -n "$sp" ]] && printf 'Spec: [%s](../spec/%s.md)\n' "$sp" "$sp"
      done
      printf '%s\n' '---'
      printf '## Description\n\n'
      emit_body "$desc"
      if [[ -n "$plan" ]];  then printf '\n## Plan\n\n';  emit_body "$plan";  fi
      if [[ -n "$tests" ]]; then printf '\n## Tests\n\n'; emit_body "$tests"; fi
      printf '\n## Execution\n%s\n' "$EXECUTION_POINTER"
    } >"$target" || die "cannot write $target" 5
    ;;

  promote | revise)
    [[ -f "$target" ]] || die "no file to $mode at $target"
    [[ -n "$plan" ]] || die "--$mode requires --plan"
    grep -qE '^## Description[[:space:]]*$' "$target" \
      || die "$target has no '## Description' — not a task artifact this script can $mode" 3

    work=$(mktemp) || die "mktemp failed"
    trap 'rm -f "$work" "$work.sec"' EXIT
    cp "$target" "$work"

    # Repair 1: a hand-written file with no header/body separator. `validate.sh`
    # calls its absence a hard ERROR, so leaving it would fail the validate call
    # at the bottom of this very script.
    if ! awk '/^---$/{found=1; exit} /^## /{exit} END{exit !found}' "$work"; then
      awk '/^## Description[[:space:]]*$/ && !done { print "---"; done=1 } { print }' \
        "$work" >"$work.tmp" && mv "$work.tmp" "$work"
    fi

    # Replace a section in place, or hold it for insertion when it is absent.
    # `## Tests` is only ever touched when the caller passed one.
    put_section() { # <heading> <body-file>
      local heading="$1" body="$2"
      if grep -qE "^${heading}[[:space:]]*\$" "$work"; then
        emit_body "$body" >"$work.body"
        awk -v h="$heading" -v bf="$work.body" '
          $0 ~ "^" h "[[:space:]]*$" {
            print h; print ""
            while ((getline l < bf) > 0) print l
            close(bf); skip = 1; next
          }
          skip && /^## / { skip = 0; print ""; print; next }
          skip { next }
          { print }
        ' "$work" >"$work.tmp" && mv "$work.tmp" "$work"
        rm -f "$work.body"
      else
        {
          printf '%s\n\n' "$heading"
          emit_body "$body"
          printf '\n'
        } >>"$work.sec"
      fi
    }
    : >"$work.sec"
    put_section '## Plan' "$plan"
    [[ -n "$tests" ]] && put_section '## Tests' "$tests"

    if [[ -s "$work.sec" ]]; then
      # Anchor. Inserting a `## Plan` into a hand-edited target that already
      # carries `## Tests` goes ABOVE that heading, not above `## Execution` —
      # the section order is Description → Plan → Tests, and anchoring on the
      # pointer alone would leave the tests sitting above the plan they belong
      # to. Everything else still anchors on `## Execution`: a `## Tests` this
      # run is inserting has no heading to sit above, and it belongs after the
      # Plan anyway.
      anchor='## Execution'
      if grep -qE '^## Plan[[:space:]]*$' "$work.sec" \
         && grep -qE '^## Tests[[:space:]]*$' "$work"; then
        anchor='## Tests'
      fi
      if grep -qE "^${anchor}[[:space:]]*\$" "$work"; then
        awk -v bf="$work.sec" -v a="$anchor" '
          $0 ~ "^" a "[[:space:]]*$" && !done {
            while ((getline l < bf) > 0) print l
            close(bf); done = 1
          }
          { print }
        ' "$work" >"$work.tmp" && mv "$work.tmp" "$work"
      else
        # Repair 2: no pointer to anchor on — append the sections, then stamp
        # the pointer after them, exactly as a fresh write does.
        {
          printf '\n'
          cat "$work.sec"
          printf '## Execution\n%s\n' "$EXECUTION_POINTER"
        } >>"$work"
      fi
    fi

    mv "$work" "$target" || die "cannot write $target" 5
    ;;
esac

echo "WROTE: $target ($mode)"
echo "VALIDATE:"
bash "$SCRIPT_DIR/../validate/validate.sh" task "$slug" 2>&1 | sed 's/^/  /'
exit 0
