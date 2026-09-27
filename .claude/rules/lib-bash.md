---
paths:
  - "skills/_lib/*.sh"
  - "skills/validate/validate.sh"
---

# Editing a bash helper

- **Ship the case with the change.** Update `tests/<helper>.test.sh` in the same commit, run `bash tests/run.sh <helper>`, then the whole suite. A comment-only or lint-only edit needs no new case.
- **macOS first.** The helpers run on macOS's stock bash 3.2 and BSD tools as well as bash 5 and GNU tools on Linux: no bash 4+ features (associative arrays, `mapfile`, `${var,,}`), no `realpath` or `readlink -f`, no GNU-only flags.
- **Check every write.** The executable helpers set `-u` but never `-e`, so a failed `mktemp`, `cp`, `mv`, `mkdir` or redirect goes unnoticed unless you test it. An unchecked `cp` once let `write-task.sh` print `WROTE:` over a destroyed file (`f190baf`).
- **Print a success line only after the operation it reports has been checked.** Callers read `WROTE:`, `OK` and the `VALIDATE:` block as facts.
- **Pin the locale where you parse bytes.** Run `awk` and `grep` under `LC_ALL=C` when the input may hold non-ASCII text: in a UTF-8 locale macOS awk aborted on a `→` and silently dropped every WARN after it (`8b8cf76`).
- **No here-string into an early-exiting command inside `$(…)`.** `grep -q <<<"$x"` in a command substitution crashed the subshell under bash 5.x, and `detect-project.sh` lost its verdict (`3ad4ad6`). Pipe instead.
- **Find the root only through `resolve-ws.sh`**, by sourcing it, and write only under the `$AI_DIR` it exports.
- **Output lines and exit codes are contract.** They are listed in `docs/contract.md` § Helpers and § validate.sh, and skills branch on them. Changing one means updating the contract and every caller that parses it.
- **A new helper** needs a row in `docs/contract.md` § Helpers, a line in the `CONTRIBUTING.md` tree, its own `tests/<name>.test.sh` (`tests/xref.test.sh` fails without one), and an `allowed-tools` rule if the model runs it.
- **shellcheck runs in CI only**, at `-S warning` (`.github/workflows/tests.yml`). Each `source` line carries a `# shellcheck source=` directive naming the file.
