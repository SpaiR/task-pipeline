# Plan a task

The plan pipeline, in one place. Two audiences:

- **`## Core`** — the pipeline itself: anchors, codebase analysis, `tests_required`, the Description/Plan/Tests draft, the self-check, the write. `to-task` Steps 3–7 point here, and so does the per-item plan agent.
- **`## Driver mode`** — what the plan agent spawned by `skills/_lib/roadmap-driver.js` does differently: its inputs, its non-interactive rules, and the parser-stable digest it must end on.

Interactive `to-task` follows `## Core` and ignores `## Driver mode`; the plan agent follows both, starting at `## Driver mode`. [docs/contract.md § task.md format](../../docs/contract.md#taskmd-format-tasktaskslugmd) is the artifact shape both produce.

## Core

### 1. Read the anchors

Read `$AI_DIR/CLAUDE.md` with a **file-read tool**, not `cat` — the platform's auto-load fires only for file-read tools. Note **Language**, **Testing Policy**, and **Code Navigation** / **Code Editing** if declared.

Then read every spec the task cites (`Spec:` headers, or the slugs collected from a roadmap item). Their decisions are **fixed anchors**: the Plan honors them and never re-derives a different technical choice. No `Spec:` at all → no anchors, proceed on the Description alone.

Then the **roadmap architecture**, when the task comes from a roadmap item. The roadmap is the one `roadmap-item.md` resolved (`to-task` Step 1a, or the path in your driver-mode prompt — present on every run, reruns included). If that roadmap carries an `## Architecture` section, read its `### Components`, its `### Interfaces between items` involving `#N`, this item's bullet under `### Item sketches`, and any `### Technical ordering` line naming `#N`. It is the **intended shape, not a fixed anchor**: the Plan's `Touches` and `Goal`s follow its components and interfaces by default, and where the code you analyze in step 2 contradicts it — a module that does not exist, a boundary that sits elsewhere — the Plan deviates, and the `Goal` of the step that deviates says why in one clause. No such section, or no roadmap → nothing to follow.

### 2. Analyze the codebase

`## Plan` steps need real paths, not paraphrase. Read code in ascending cost order per `.task/CLAUDE.md` → Code Navigation (its MCP tools first when declared, built-ins as fallback):

1. Structural overview of the modules/files the task names or implies.
2. Symbol bodies — only those directly affected.
3. Dependencies and usage locations.
4. Existing patterns in neighbouring code, for reuse.
5. Impact on adjacent modules.

Reads at the same level are independent — issue them as one parallel batch, not one round-trip at a time. **Stop as soon as you can name every file each step will touch and how**; deeper investigation belongs to the implementing session's own reasoning.

### 3. Resolve `tests_required`

From `.task/CLAUDE.md` → Testing Policy: `always` → `true`; `never` → `false`; `on-demand` → `true` only when the Description (or the chat, or the item's ready description) explicitly asks for tests — "with tests", "add tests", "cover with tests".

Two remaining `on-demand` cases, resolved distinctly:

- **Silent** — nothing about tests anywhere → `false`, no prompt.
- **Testing-adjacent but unclear** — tests are mentioned, but not whether *new* ones are wanted → interactive callers resolve it with one `AskUserQuestion`: **Add tests** / **No tests this run**. In driver mode there is nobody to ask: default to `false`.

### 4. Draft the Description, Plan and Tests

- `## Description` — the why + the what, per `.task/CLAUDE.md` → Language (section labels themselves stay English). From a roadmap item: derive it from the item's ready description as `roadmap-item.md` step 3 maps it. Fabricate nothing that was not actually discussed or written down.
- `## Plan` — `### Step N:` blocks, three layers:

  ```markdown
  ### Step 1: {short action title}

  **Goal:** {the observable end state this step reaches — detailed enough to
  execute against without guessing. Do not compress a nuanced step into one
  line; do not pad a simple one either.}

  **Touches:**

  - `{full path}`
  - `{full path}` ({symbol}, {symbol})

  **Logic:** {optional — pseudocode for non-obvious branching only. Omit
  entirely when Goal + Touches leave no ambiguity.}
  ```

  Each field starts its own paragraph, after a blank line — adjacent lines merge into one paragraph in a Markdown preview. `Touches` is a bulleted list, one file per bullet: full paths from the project root, and where a file holds more than one unrelated concern, the symbol(s) touched in parentheses after the path. A new file: `Goal` states its role, `Touches` still names it. `Logic` is the only place a pseudocode block or a `...` placeholder belongs. Order steps so none depends on a fact only a later step establishes.
- `## Tests` — only when `tests_required`. `### Test N: {what is asserted}` plus one line: the file path and the arrange/act/assert in prose, no code (the implementing session writes the real test). Each Plan step that satisfies a test references it by number in its `Goal`. When `tests_required` is `false`, omit the heading entirely — never leave an empty one.

**Not part of the format:** no `Implement-Model:` stamp (model hints live only on roadmap items, as `**Model:**`), no `## Verification`, no `## Risks`.

### 5. Self-check

Against the draft, before writing — fix inline rather than writing something already known to be broken:

- [ ] Does `## Description` state the why, not just the what?
- [ ] Does every `### Step N:` carry a non-empty `**Touches:**` list with at least one real path?
- [ ] Does each `**Goal:**` / `**Touches:**` / `**Logic:**` start after a blank line, with `Touches` as one bullet per file?
- [ ] Is `**Logic:**` present only where Goal + Touches genuinely leave ambiguity?
- [ ] `tests_required` true → is `## Tests` present, and does every step that satisfies a test name it by number?
- [ ] `tests_required` false → is `## Tests` fully absent, with no empty heading?
- [ ] Are the pinned spec decisions honored rather than silently overridden?
- [ ] When the roadmap has `## Architecture`: does the Plan follow it, and does every step that departs from it state why in its `Goal`?
- [ ] No `TBD` / `TODO` / `???` outside a `Logic` block?
- [ ] Are the steps ordered so nothing depends on a not-yet-established fact?

### 6. Write

`skills/_lib/write-task.sh` writes the file and validates it in one call. It owns the header link forms, the `---` separator, the section order and the single stamped `## Execution` pointer, and it resolves `$AI_DIR` itself — so nothing here assembles the artifact or re-resolves the root. Bodies go in through **quote-delimited** heredocs, written flush-left (so backticks and `$` reach the file verbatim), each holding the section body **without** its `## …` heading:

```bash
fail() { echo "ERROR write-task: $1" >&2; rm -f "$d" "$p" "$t"; exit 5; }
d=$(mktemp) && p=$(mktemp) && t=$(mktemp) || fail "cannot create temp files"
cat >"$d" <<'DESC' || fail "cannot write the description"
{drafted Description body}
DESC
cat >"$p" <<'PLAN' || fail "cannot write the plan"
{drafted ### Step N: blocks}
PLAN
cat >"$t" <<'TESTS' || fail "cannot write the tests"
{drafted ### Test N: blocks — omit this heredoc and --tests when tests_required is false}
TESTS
# --roadmap and --item: from a roadmap item only
bash "<plugin root>/skills/_lib/write-task.sh" \
  --slug <slug> --title "{Title}" \
  --description "$d" --plan "$p" --tests "$t" \
  --roadmap <roadmap-slug> --item <N> \
  --spec <spec-slug>   # one per cited spec, any source
rc=$?; rm -f "$d" "$p" "$t"; exit "$rc"
```

The file is always written whole, never edited in place. `--title`, `--description` and `--plan` are required; drop `--roadmap` / `--item` when the source is the chat, and `--spec` when nothing is cited.

It refuses to overwrite rather than guessing, and writes nothing when it does: **exit 4** — the slug already exists. `--force` overrides, and is only ever earned by a caller's collision guard: `to-task`'s overwrite chip, or the driver's header match on its own item's file (D2).

**Exit 5** is the one write failure that is not a refusal — an unwritable `$AI_DIR`, a full disk, or the recipe's own temp files that could not be created or written (`ERROR write-task: cannot …`). Nothing was written and no `WROTE:` line was printed: report that plainly instead of a digest, and never claim a path that does not exist. The recipe ends in `exit "$rc"` so the Bash call carries `write-task.sh`'s own status; a trailing `rm` would report 0 whatever happened. Any other non-zero exit is a failure too, never a write.

The `WROTE:` / `VALIDATE:` lines it prints are what the caller's digest reports. Only a setup-precondition failure is fatal — in driver mode a `FAIL` in D3. Its signal is the line `ERROR precondition: CLAUDE.md not found` inside the `VALIDATE:` block: `write-task.sh` exits 0 once the file is written, so validate's own exit code never reaches the caller.

## Driver mode

Instructions for `roadmap-to-workflow`'s per-item **plan agent**, spawned by `skills/_lib/roadmap-driver.js`. Same output contract as the `to-task` skill, none of the interactive machinery.

**Inputs (from your prompt):** the roadmap file (absolute path), the roadmap slug, the item `#N` and its title, the `.task` directory (`AI_DIR`), the plugin root, and the roadmap-level spec file paths + slugs.

**Ground rules:** you are non-interactive — never ask, never block on a prompt, make constructive assumptions. Do **not** implement, commit, tick any checkbox, or modify any file other than the one task file you write. Your final text is parsed by a driver, not read by a human.

### D1. Resolve the item

Follow `skills/_lib/roadmap-item.md` — steps 3 to 6 (read the ready description, collect the specs, derive the slug, note the architecture). Its steps 1 and 2 do not apply: the roadmap path and your `#N` arrive in the prompt.

### D2. Slug collision, without anyone to ask

`roadmap-item.md` step 5 already separates the two cases. Your prompt carries no `TASKS:` list, so check whether `$AI_DIR/task/<item-slug>.md` exists before writing — a rerun after a failed implement finds this item's own file there, and writing it without `--force` would exit 4. In driver mode:

- **This item's earlier capture** → regenerate it: write fresh with `--force`. The Description is re-derived from the item's ready description, exactly as `to-task`'s regenerate chip does, so an item edited since the failed run is planned from its new text. The header match in `roadmap-item.md` step 5 is the collision guard that earns the `--force`.
- **An unrelated task on the same kebab-case** → disambiguate the slug per `roadmap-item.md` step 5, which checks the new slug the same way — an earlier run of this item may already have written its file under that disambiguated slug, and then it is this item's own capture after all. Write fresh; `--force` only on that header match, never over a namesake.
- **`write-task.sh` exits 4 anyway** → report `FAIL` in D3 and name the slug. There is nobody to ask, so a destructive fallback is never the answer.

### D3. Run `## Core`, then the digest

Work `## Core` steps 1–6 with the item's ready description as the Description source. A write that exits non-zero — 4 above, 5, or any other status — is a `FAIL` naming the `ERROR write-task:` line, with no digest above it. Otherwise print a 2–4 line digest — path written, step count, validate result. **No `→ Next:` footer, nothing after the last line.** The last non-empty line MUST be exactly one of:

```
OK #{N} {item-slug} planned
FAIL #{N} {item-slug} {what failed}
```

Emit one of the two even on failure: the driver reads only this line, and takes `{item-slug}` from it.
