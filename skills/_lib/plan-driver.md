# Plan a task

The plan pipeline, in one place. Two audiences:

- **`## Core`** — the pipeline itself: anchors, codebase analysis, `tests_required`, the Description/Plan/Tests draft, the self-check, the write. `to-plan` Steps 3–7 point here, and so does the per-item plan agent.
- **`## Driver mode`** — what the plan agent spawned by `skills/_lib/roadmap-driver.js` does differently: its inputs, its non-interactive rules, and the parser-stable digest it must end on.

Interactive `to-plan` follows `## Core` and ignores `## Driver mode`; the plan agent follows both, starting at `## Driver mode`. [docs/contract.md § task.md format](../../docs/contract.md#taskmd-format-tasktaskslugmd) is the artifact shape both produce.

## Core

### 1. Read the anchors

Read `$AI_DIR/CLAUDE.md` with a **file-read tool**, not `cat` — the platform's auto-load fires only for file-read tools. Note **Language**, **Testing Policy**, and **Code Navigation** / **Code Editing** if declared.

Then read every spec the task cites (`Spec:` headers, or the slugs collected from a roadmap item). Their decisions are **fixed anchors**: the Plan honors them and never re-derives a different technical choice. No `Spec:` at all → no anchors, proceed on the Description alone.

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

- `## Description` — the why + the what, per `.task/CLAUDE.md` → Language (section labels themselves stay English). From a roadmap item: the why from `### Context`, the what from Goal / Outcomes / Invariants / Acceptance criteria. Fabricate nothing that was not actually discussed or written down. In promote / revise the Description already exists and is inherited as-is.
- `## Plan` — `### Step N:` blocks, three layers:

  ```markdown
  ### Step 1: {short action title}
  **Goal:** {the observable end state this step reaches — detailed enough to
  execute against without guessing. Do not compress a nuanced step into one
  line; do not pad a simple one either.}
  **Touches:** `{full path}` `{full path}` {…every file this step changes}
  **Logic:** {optional — pseudocode for non-obvious branching only. Omit
  entirely when Goal + Touches leave no ambiguity.}
  ```

  Full paths from the project root in `Touches`, and where a file holds more than one unrelated concern, name the symbol(s) touched beside the path. A new file: `Goal` states its role, `Touches` still names it. `Logic` is the only place a pseudocode block or a `...` placeholder belongs. Order steps so none depends on a fact only a later step establishes.
- `## Tests` — only when `tests_required`. `### Test N: {what is asserted}` plus one line: the file path and the arrange/act/assert in prose, no code (the implementing session writes the real test). Each Plan step that satisfies a test references it by number in its `Goal`. When `tests_required` is `false`, omit the heading entirely — never leave an empty one.

**Not part of the format:** no `Implement-Model:` stamp (model hints live only on roadmap items, as `**Model:**`), no `## Verification`, no `## Risks`.

### 5. Self-check

Against the draft, before writing — fix inline rather than writing something already known to be broken:

- [ ] Does `## Description` state the why, not just the what? (Fresh capture only.)
- [ ] Does every `### Step N:` carry a non-empty `**Touches:**` with at least one real path?
- [ ] Is `**Logic:**` present only where Goal + Touches genuinely leave ambiguity?
- [ ] `tests_required` true → is `## Tests` present, and does every step that satisfies a test name it by number?
- [ ] `tests_required` false → is `## Tests` fully absent, with no empty heading?
- [ ] Are the pinned spec decisions honored rather than silently overridden?
- [ ] No `TBD` / `TODO` / `???` outside a `Logic` block?
- [ ] Are the steps ordered so nothing depends on a not-yet-established fact?

### 6. Write

`skills/_lib/write-task.sh` writes the file and validates it in one call. It owns the header link forms, the `---` separator, the section order and the single stamped `## Execution` pointer, and it resolves `$AI_DIR` itself — so nothing here assembles the artifact or re-resolves the root. Bodies go in through **quote-delimited** heredocs, written flush-left (so backticks and `$` reach the file verbatim), each holding the section body **without** its `## …` heading:

```bash
d=$(mktemp); p=$(mktemp); t=$(mktemp)
cat >"$d" <<'DESC'
{drafted Description body}
DESC
cat >"$p" <<'PLAN'
{drafted ### Step N: blocks}
PLAN
cat >"$t" <<'TESTS'
{drafted ### Test N: blocks — omit this heredoc and --tests when tests_required is false}
TESTS
bash "<plugin root>/skills/_lib/write-task.sh" --fresh \
  --slug <slug> --title "{Title}" \
  --description "$d" --plan "$p" --tests "$t" \
  --roadmap <roadmap-slug> --item <N> --spec <spec-slug>   # from a roadmap item only; repeat --spec per cited spec
rm -f "$d" "$p" "$t"
```

Three modes, one per situation:

- **`--fresh`** — a new file. `--title` and `--description` required; drop `--roadmap` / `--item` when the source is the chat, and `--spec` when nothing is cited.
- **`--promote`** — an existing Description-only file gains `## Plan` (+ `## Tests`, if this run adds them), inserted directly above `## Execution`. Header, separator, Description and pointer untouched.
- **`--revise`** — an existing `## Plan` is replaced. Pass `--tests` **only** when this run's edit touches the tests; without it the existing `## Tests` is left byte-for-byte as it was.

It refuses the destructive cases rather than guessing, and writes nothing when it does: **exit 4** — `--fresh` on a slug that already exists (`--force` overrides, and is only ever earned by a caller's collision guard); **exit 3** — the promote/revise target has no `## Description`, so it is not a task artifact to extend. A hand-edited target that lost its `---` separator or its `## Execution` pointer is repaired on the way through; do not pre-patch it.

The `WROTE:` / `VALIDATE:` lines it prints are what the caller's digest reports. Only a setup-precondition failure (validate exit 2) is fatal.

## Driver mode

Instructions for `roadmap-to-workflow`'s per-item **plan agent**, spawned by `skills/_lib/roadmap-driver.js`. Same output contract as the `to-plan` skill, none of the interactive machinery.

**Inputs (from your prompt):** the roadmap file (absolute path), the roadmap slug, the item `#N` and its title, the pipeline root (`AI_DIR`), the plugin root, and the roadmap-level spec file paths + slugs.

**Ground rules:** you are non-interactive — never ask, never block on a prompt, make constructive assumptions. Do **not** implement, commit, tick any checkbox, or modify any file other than the one task file you write. Your final text is parsed by a driver, not read by a human.

### D1. Resolve the item

Follow `skills/_lib/roadmap-item.md` — steps 3, 4 and 5 (read the ready description, collect the specs, derive the slug). Its steps 1 and 2 do not apply: the roadmap path and your `#N` arrive in the prompt.

### D2. Slug collision, without anyone to ask

`roadmap-item.md` step 5 already separates the two cases. In driver mode:

- **This item's earlier capture** → `--promote` it (no `## Plan` yet) or `--revise` it (one already present).
- **An unrelated task on the same kebab-case** → disambiguate the slug and write fresh. Never overwrite, never `--force`.
- **`write-task.sh` exits 3 or 4 anyway** → report `FAIL` in D3 and name the slug. There is nobody to ask, so a destructive fallback is never the answer.

### D3. Run `## Core`, then the digest

Work `## Core` steps 1–6 with the item's ready description as the Description source. Then print a 2–4 line digest — path written, step count, validate result. **No `→ Next:` footer, nothing after the last line.** The last non-empty line MUST be exactly one of:

```
OK #{N} {item-slug} planned
FAIL #{N} {item-slug} {what failed}
```

Emit one of the two even on failure: the driver reads only this line, and takes `{item-slug}` from it.
