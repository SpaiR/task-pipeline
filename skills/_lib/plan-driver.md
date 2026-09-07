# Plan an item — driver mode

Instructions for `roadmap-to-workflow`'s per-item **plan agent** (spawned by `skills/_lib/roadmap-driver.js`). This is the non-interactive counterpart of the `to-plan` skill: same output contract, none of the interactive machinery. **Sync obligation:** this file mirrors [docs/contract.md § task.md format](../../docs/contract.md#taskmd-format-tasktaskslugmd) and `to-plan`'s Steps 3–7 — a change to either owner changes this file in the same commit.

**Inputs (from your prompt):** the roadmap file (absolute path), the roadmap slug, the item `#N` and its title, the pipeline root (`AI_DIR`), the plugin root, and the roadmap-level spec file paths + slugs.

**Ground rules:** you are non-interactive — never ask, never block on a prompt, make constructive assumptions. Do **not** implement, commit, tick any checkbox, or modify any file other than the one task file you write. Your final text is parsed by a driver, not read by a human — end with the exact digest line in step 8.

## 1. Resolve the item

Open the roadmap file and find the `### - [ ] N.` heading for your item. Read its `**Ready description:**` blockquote — its sub-headings are quoted (`> ### Context` / `> ### Goal` / `> ### Outcomes` / `> ### Invariants` / `> ### Acceptance criteria`); strip the `> ` prefix as you read. `### Context` becomes the Description's "why"; the rest folds into the "what". `### Acceptance criteria` entries are good candidates to carry into `## Tests` verbatim as test intents when tests are required.

Collect the specs the item relies on: any `### Spec references → [<spec-slug>](../spec/<spec-slug>.md) §N` in the item body, **plus** the roadmap-level specs from your prompt. Read a slug from the link **text**, never by following the link target (the target is relative to the roadmap file's directory, not your cwd; an older or hand-edited roadmap may carry a bare `<spec-slug>` — read it the same way).

## 2. Slug and collision (non-interactive)

Derive `<item-slug>`: kebab-case English, 2–4 words, from the **item's** title (not the roadmap's).

If `<AI_DIR>/task/<item-slug>.md` already exists, read its header before writing:

- Its `Roadmap:` link **text** matches this roadmap's slug **and** `Source item: #N` matches your item → it is this item's earlier capture. Edit it **in place**: no `## Plan` heading yet → insert `## Plan` (and `## Tests`, if required) between `## Description`'s content and the existing `## Execution` pointer; `## Plan` already present → replace that whole block (and `## Tests` only if your draft changes it). Never touch the header lines, the `---` separator, `## Description`, or `## Execution`.
- Different headers, or none → an unrelated task that merely kebab-cases the same title. Disambiguate `<item-slug>` with a short qualifier (append a second distinguishing word) — **never overwrite it**.

## 3. Read the anchors

Read `<AI_DIR>/CLAUDE.md` with a file-read tool (not `cat` — the platform's auto-load fires only for file-read tools) and note **Language**, **Testing Policy**, and **Code Navigation** / **Code Editing** if present. Read every spec file from step 1 and your prompt: their decisions are **fixed anchors** — the Plan must honor them, never re-derive a different technical choice.

## 4. Analyze the codebase

`## Plan` steps need real paths, not paraphrase. Read code in ascending cost order per `.task/CLAUDE.md` → Code Navigation (MCP tools first when declared, built-ins as fallback):

1. Structural overview of the modules/files the item names or implies.
2. Symbol bodies — only those directly affected.
3. Dependencies and usage locations.
4. Existing patterns in neighboring code for reuse.
5. Impact on adjacent modules.

Batch independent reads in parallel. **Stop as soon as you can name every file each step will touch and how** — deeper investigation belongs to the implementing session.

## 5. Resolve `tests_required`

From `.task/CLAUDE.md` → Testing Policy: `always` → `true`; `never` → `false`; `on-demand` → `true` only if the Ready description explicitly asks for tests ("with tests", "add tests"). **Any ambiguity → `false`** — there is no user to ask.

## 6. Draft Description, Plan, Tests

- `## Description` — the why (from Context) + the what (from Goal/Outcomes/Invariants/Acceptance criteria), written per `.task/CLAUDE.md` → Language (section labels stay English). Do not fabricate anything the roadmap doesn't say.
- `## Plan` — `### Step N:` blocks:

  ```markdown
  ### Step 1: {short action title}
  **Goal:** {the observable end state — detailed enough to execute without guessing}
  **Touches:** `{full path}` `{full path}`
  **Logic:** {optional pseudocode for non-obvious branching only; omit otherwise}
  ```

  Full paths from the project root in `Touches`; where a file holds more than one concern, name the symbol(s) touched. `Logic` is the only place pseudocode or `...` belongs. Order steps so no step depends on a fact only a later step establishes.
- `## Tests` (only if `tests_required`) — `### Test N: {what is asserted}` plus one line: file path and the arrange/act/assert in prose, no code. Each Plan step that satisfies a test references it by number in its `Goal`. If `tests_required` is `false`, omit the heading entirely.

Self-check before writing: every step has a non-empty `**Touches:**` with real paths; spec pins honored; no placeholders (`TBD`, `TODO`, `???`) outside a `Logic` block; no empty `## Plan` / `## Tests` headings.

## 7. Write and validate

`skills/_lib/write-task.sh` writes the file and validates it in one call. It owns the header link forms, the `---` separator, the section order and the stamped `## Execution` pointer, so none of that is assembled here — see docs/contract.md § task.md format for the shape it produces. Pass the absolute plugin root and let it resolve `AI_DIR` itself; never write a cwd-relative `.task/`.

Bodies go in via **quote-delimited** heredocs, written flush-left, each holding the section body **without** its `## …` heading:

```bash
d=$(mktemp); p=$(mktemp); t=$(mktemp)
cat >"$d" <<'DESC'
{drafted Description body}
DESC
cat >"$p" <<'PLAN'
{drafted ### Step N: blocks}
PLAN
cat >"$t" <<'TESTS'
{drafted ### Test N: blocks — omit this heredoc and --tests unless tests_required}
TESTS
bash "<plugin root>/skills/_lib/write-task.sh" --fresh \
  --slug <item-slug> --title "{Item title}" \
  --description "$d" --plan "$p" --tests "$t" \
  --roadmap <roadmap-slug> --item <N> --spec <spec-slug>   # repeat --spec per cited + roadmap-level spec
rm -f "$d" "$p" "$t"
```

Exit 4 means that slug already exists and nothing was written: this is a non-interactive run with nobody to ask, so do **not** pass `--force` — report `FAIL` in step 8 and name the slug. Exit 3 (target has no `## Description`) is the same story. Otherwise mention the `VALIDATE:` WARN/ERROR lines in your digest; only a setup-precondition failure (validate exit 2) is fatal.

## 8. Output — parser-stable digest

Print a 2–4 line digest (path written, step count, validate result). **No `→ Next:` footer, nothing after the last line.** The last non-empty line MUST be exactly one of:

```
OK #{N} {item-slug} planned
FAIL #{N} {item-slug} {what failed}
```

Emit one of the two even on failure — the driver reads only this line, and takes `{item-slug}` from it.
