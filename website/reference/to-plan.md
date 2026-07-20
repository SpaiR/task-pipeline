# to-plan

Distils the chat (or a roadmap item) into `.task/task/<slug>.md` with `## Description` **and** `## Plan` (Goal / Touches / Logic steps), plus `## Tests` when the testing policy calls for it. The deepest one-task capture.

See the [single-task guide](/guide/single-task) for how promote/revise work in practice.

## Usage

```text
/task:to-plan [<context>]
```

**Input** — `$ARGUMENTS`, optional. Recognized forms:

| Form | Behavior |
|---|---|
| *(empty)* | Draft from the chat, or continue a task this conversation is clearly about. |
| `<slug>` or a path | Target that existing `.task/task/<slug>.md` directly (promote or revise). |
| `<roadmap-slug>` or `<roadmap-slug>#<N>` | Open from that roadmap item. |
| anything else | Free-form context folded into the draft. |

## Three modes on an existing file

`to-plan` behaves differently depending on the target's current state — no flag needed:

- **Fresh** — no file yet → writes a new task with Description + Plan.
- **Promote** — file has a Description but no Plan → inserts `## Plan` in place, leaving the Description untouched.
- **Revise** — file already has a Plan → replaces it in place, with a one-line note of what changed.

## The Plan step contract

```markdown
### Step 1: {short action title}
**Goal:** {the observable end state this step reaches}
**Touches:** `path/one` `path/two`
**Logic:** {optional — pseudocode, only when the how is non-obvious}
```

`Touches` lists real full paths — and also scopes which `/code-review` fixes the executing session applies. `Logic` appears only where Goal + Touches leave genuine ambiguity.

## Tests

Governed by `config.md` → Testing Policy: `always` writes Tests every time; `on-demand` (default) only when the discussion asks; `never` omits them. Each `## Plan` step that satisfies a test references it by number.

## Output

```text
Wrote `.task/task/http-retry-backoff.md`  (fresh)
# HTTP retry with backoff
Sections: Description, Plan (3 steps), Execution
Plan:
- Step 1: {short title}
- Step 2: …
validate: OK — 0 errors, 0 warnings

→ Next: implement it now, or in a fresh session run:
  `implement .task/task/http-retry-backoff.md`
```

## Does not

- Overwrite the Description in promote/revise mode — only `## Plan` (and, narrowly, `## Tests`) are in scope there.
- Modify the source roadmap file or a referenced spec — both are read-only here.
- Leave `## Plan` present with zero steps, or `## Tests` with zero tests — both fail `validate.sh`.
- Stamp a model hint — model hints live only on roadmap items as `**Model:**`.
