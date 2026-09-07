#!/usr/bin/env bash
# detect-project.sh — print the facts first-run setup needs, so it chooses from
# a list instead of going looking.
#
# Usage: bash detect-project.sh [dir]     (default: cwd)
#
# Everything here is a lookup: which manifests exist, which commands they
# already declare, where the project documents its commit convention, and which
# natural language its own prose is in. `setup.md` step 2 reads the block and
# picks; it never has to guess a build command that is written down.
#
# Output (fixed line prefixes, English, always in this order):
#   ROOT: <abs>
#   MANIFEST: <file> …                  | none
#   COMMANDS: <source>: <name> …        | none          (one line per source)
#   COMMIT_FORMAT_DOC: <path>           | none
#   TEST_CONVENTION: <path>: <line>     | none          (a documented TDD rule)
#   README_LANG: <ascii|non-ascii> …
#   COMMIT_LANG: <ascii|non-ascii> …
#   PROJECT_CLAUDE_MD: present | absent
#
# The two `*_LANG` lines report evidence, not a verdict: whether the project's
# own prose is plain ASCII (English or transliterated) or carries non-ASCII
# script, with a sample. Naming the language is the model's call — this is what
# `git log` and `README.md` actually contain.
#
# Exit 0 whenever the block printed; 2 on a bad argument.
set -u

dir="${1:-.}"
[[ -d "$dir" ]] || { echo "ERROR usage: detect-project.sh [dir] — no such directory: $dir" >&2; exit 2; }
cd "$dir" || { echo "ERROR usage: cannot enter $dir" >&2; exit 2; }

echo "ROOT: $(pwd)"

# --- manifests ---------------------------------------------------------------
manifests=()
for f in package.json pyproject.toml setup.py requirements.txt Cargo.toml go.mod \
         build.gradle build.gradle.kts pom.xml Gemfile composer.json Makefile \
         justfile Taskfile.yml CMakeLists.txt mix.exs deno.json; do
  [[ -f "$f" ]] && manifests+=("$f")
done
if (( ${#manifests[@]} == 0 )); then
  echo "MANIFEST: none"
else
  echo "MANIFEST: ${manifests[*]}"
fi

# --- commands the project already declares -----------------------------------
# Names only. The model composes the actual invocation (`npm run test`,
# `make lint`) — inventing a runner is the one thing it cannot get wrong here.
cmd_lines=0
if [[ -f package.json ]]; then
  # Keys of the `"scripts"` object only, and only until its closing brace. The
  # scan starts at the text AFTER the opening `{` and loops within a line, so a
  # compact `"scripts": { "test": "jest", "build": "tsc" },` reports its own two
  # names instead of dropping them and then harvesting the next object's keys as
  # if they were scripts — which is how a `npm run <a-dependency-name>` reached
  # `.task/CLAUDE.md` → Build and Tests.
  scripts=$(awk '
    !inb && match($0, /"scripts"[[:space:]]*:[[:space:]]*\{/) {
      inb = 1; $0 = substr($0, RSTART + RLENGTH)
    }
    inb {
      line = $0
      if (match(line, /\}/)) { line = substr(line, 1, RSTART - 1); fin = 1 }
      while (match(line, /"[^"]+"[[:space:]]*:/)) {
        s = substr(line, RSTART + 1, RLENGTH - 1); sub(/"[[:space:]]*:$/, "", s)
        out = (out == "" ? s : out " " s)
        line = substr(line, RSTART + RLENGTH)
      }
      if (fin) exit
    }
    END { print out }
  ' package.json)
  [[ -n "$scripts" ]] && { echo "COMMANDS: package.json scripts: $scripts"; cmd_lines=1; }
fi
if [[ -f Makefile ]]; then
  # Real targets only: a name at line start followed by `:`, skipping pattern
  # rules, variable assignments and `.PHONY`-style specials.
  targets=$(awk '
    # `:$` as well as `:[^=]`, so a target with no prerequisites still counts;
    # `[^=]` keeps `VAR := value` assignments out.
    /^[a-zA-Z0-9_.\/-]+[[:space:]]*:([^=]|$)/ {
      t = $0; sub(/[[:space:]]*:.*$/, "", t)
      if (t ~ /^\./ || t ~ /%/ || seen[t]++) next
      out = (out == "" ? t : out " " t)
    }
    END { print out }
  ' Makefile)
  [[ -n "$targets" ]] && { echo "COMMANDS: Makefile targets: $targets"; cmd_lines=1; }
fi
(( cmd_lines == 0 )) && echo "COMMANDS: none"

# --- commit-format doc, in the order setup.md checks -------------------------
commit_doc="none"
for f in CONTRIBUTING.md docs/CONTRIBUTING.md .github/CONTRIBUTING.md; do
  [[ -f "$f" ]] && { commit_doc="$f"; break; }
done
echo "COMMIT_FORMAT_DOC: $commit_doc"

# --- a documented TDD convention (the only thing that earns `always`) --------
conv="none"
for f in CLAUDE.md CONTRIBUTING.md docs/CONTRIBUTING.md .github/CONTRIBUTING.md README.md; do
  [[ -f "$f" ]] || continue
  hit=$(grep -n -i -m1 -E 'test[- ]driven|write the test first|tests? (are|is) (mandatory|required)|TDD' "$f" 2>/dev/null)
  [[ -n "$hit" ]] && { conv="$f: $hit"; break; }
done
echo "TEST_CONVENTION: $conv"

# --- language evidence, not a verdict ----------------------------------------
lang_of() { # <text> → "ascii" | "non-ascii"
  LC_ALL=C grep -q '[^[:print:][:space:]]' <<<"$1" && echo "non-ascii" || echo "ascii"
}
readme_sample=""
for f in README.md readme.md; do
  [[ -f "$f" ]] && { readme_sample=$(grep -v '^[[:space:]]*$' "$f" | grep -v '^#' | head -3 | tr '\n' ' '); break; }
done
if [[ -n "$readme_sample" ]]; then
  echo "README_LANG: $(lang_of "$readme_sample") — ${readme_sample:0:120}"
else
  echo "README_LANG: none"
fi
if git rev-parse --git-dir >/dev/null 2>&1; then
  log_sample=$(git log -10 --pretty=%s 2>/dev/null | tr '\n' ' ')
  if [[ -n "$log_sample" ]]; then
    echo "COMMIT_LANG: $(lang_of "$log_sample") — ${log_sample:0:120}"
  else
    echo "COMMIT_LANG: none (no commits yet)"
  fi
else
  echo "COMMIT_LANG: none (not a git repository)"
fi

[[ -f CLAUDE.md ]] && echo "PROJECT_CLAUDE_MD: present" || echo "PROJECT_CLAUDE_MD: absent"
