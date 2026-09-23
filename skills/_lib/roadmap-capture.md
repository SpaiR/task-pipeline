# Capture a roadmap

The roadmap capture flow, in one place. `to-roadmap` owns its Step 0 setup gate and its digest; everything between — the precondition, context, harvest or brainstorm, the draft, the save and the post-save self-check — is `## Core` below, and `to-roadmap` Steps 1–5 point here. [docs/contract.md § Roadmap file format](../../docs/contract.md#roadmap-file-format-taskroadmapslugmd) is the artifact shape it produces.

**From the caller:** Step 0's `AI_DIR:` (every `.task/roadmap/<slug>.md` below means `$AI_DIR/roadmap/<slug>.md`, never a cwd-relative path) and its `ROADMAPS:` list, which step 1 reads for structural style and step 4 for the slug collision — neither needs a listing call of its own. The digest printed after step 5 is the caller's.

## Core

### Precondition

- **Too small for a roadmap** — no obvious phases, no inter-task dependencies, fewer than ~3 atomic steps → **stop and suggest** `/task:to-task` or `/task:to-plan`. Say plainly that nothing was written; after several brainstorm rounds the user cannot otherwise tell whether a half-roadmap now exists. Carry **both** options with the reason: "This is one task, not an initiative — no phases, no cross-item dependencies. Nothing was written. `→ Next: \`/task:to-plan\` to capture it with a plan, or \`/task:to-task\` for the what-and-why only.`"

(The slug-collision check runs at save time, once the slug is derived — see step 4.)

### 1. Load context

One parallel batch, since none of these depends on another: `.task/CLAUDE.md` (Language, conventions), the project's `CLAUDE.md` if present, and the `docs/` top level. Structural style comes from the caller's `ROADMAPS:` list — open one only when this initiative may overlap it, and declare that one as a Prerequisite. No source files: this is a shallow scan, not investigation.

### 2. Cold start or harvest

**Branch first** — where the decisions come from matters:

- **Harvest** — this conversation already settled concrete decisions about **this same initiative**, small details included. Tells: "build a roadmap from what we discussed", or `$ARGUMENTS` reading as a handle for prior discussion. → 2H.
- **Cold start** — a rough few-line description, no prior initiative-specific discussion. → 2C.

On the fence, prefer harvest: a false positive costs one recap the user skims, a false negative silently drops details.

#### 2H. Harvest — Decision Inventory

Comb the prior conversation and print, as message text in your reply (chat-only, never written to a file; heading skeleton English, prose in the language from `.task/CLAUDE.md`):

```
## Roadmap — Decision Inventory

{Building this roadmap from our discussion — here is every decision I
captured. Say so if a line is wrong.}

### Decisions locked so far
1. {one locked decision at full specificity — small details included
   verbatim, e.g. "the button is first in the panel"}
2. {...}

### Open forks (not yet decided)
- {unresolved question left by the discussion}

### Coverage caveat
{Only if part of the discussion is out of context — a false alarm
erodes trust. Omit the heading otherwise.}
```

It is a **recap** of decisions the user already reached: print it, no confirmation chip. Open forks left → resolve them in one focused round (2C's shape) first, then draft. A misread arrives as chat: correct it and reprint before drafting.

#### 2C. Cold start — brainstorm round

```
## Roadmap — Round 1

### Initiative as I understand it
{2–4 sentences, including scope ambition.}

### Decomposition options
**A) {name}** — {sketch}
- Phases: {...}
- Pros / Cons: {...}
- Fits when: {...}

**B) {alternative}** — {sketch}
...

### My recommendation
{2–4 sentences, a real opinion, not a hedge.}

### Risks and forks I want to flag
- {specific to this initiative — not generic}

### What I need from you
{One focused question on the most load-bearing fork.}
```

Always **2–3 decomposition options** with different phase boundaries — behavioral milestones, observable state changes, not technical layers like "substrate" vs "UI". Iterate as `Round N`, same structure, narrowed to the fork in focus. A round is **content dialogue, not a path fork**: print it as message text and close on the open question, because convention (c)'s chips would flatten the pros and cons the round exists to show. Typical depth 3–6 rounds; past 6, say the initiative is too big and suggest splitting. Stop when the user says "write it", or when another round would only restate conclusions.

**Track decisions as you go, not in your head.** Two kinds surface: **behavioral** ones, observable properties the user locked in, which land in an item's `### Outcomes` / `### Acceptance criteria`; and **technical anchors** — a protocol, a cross-cutting data shape, a "we picked X over Y because…" whose reasoning would not survive re-derivation — which belong in a standalone spec, never in an item body. Step 3 routes both.

Before drafting, reprint the full list as message text — the cold-start twin of 2H's inventory, no confirmation chip. Topics the user said to skip stay skipped.

### 3. Draft the file

Once the 2H inventory (or the 2C recap) is **printed** — no reply is awaited; a correction arrives as chat, and you reprint before drafting — draft the whole file per [contract § Roadmap file format](../../docs/contract.md#roadmap-file-format-taskroadmapslugmd), which owns the section skeleton, the item grammar and the link rules. Two things it is easy to get wrong:

- `**Dependencies:**` is an em dash `—` for none, otherwise a comma-separated list of item numbers. Any other word reads as a dependency on a missing item and hard-stops the autopilot.
- A `**Ready description:**` blockquote must stand alone, and its sub-headings are **quoted** (`> ### Context`, …). `validate.sh` treats a bare unquoted one as a hard error, because `to-plan` strips the `> ` prefix to find the body.

**Route every confirmed decision to a home:**

- Observable behavior / user-facing effect → the item's `### Outcomes`, or `### Acceptance criteria` when it's a testable assertion.
- Cross-item technical decision → a standalone spec. One that already exists gets a `Spec:` header line **directly under `# <Title>`**, above the intro, plus a `### Spec references → [<spec-slug>](../spec/<spec-slug>.md) §N` citation in each steered item. One that does not exist is **not written here**: surface the decision with a one-line recommendation to capture it via `/task:to-spec`, and reference it on a later run.
- Scope exclusion → `## Out of scope`, with the reason.
- Anything else → drop it, but say so to the user with a one-line reason — never a silent omission.

Reserve specs for choices that would break cross-item consistency if a later `/task:to-plan` re-derived them differently. A single-item detail is that item's `### Outcomes` / `### Acceptance criteria`, never a spec.

**`**Model:**` is optional** — only with a real basis: pure content editing → `haiku`, a new subsystem or cross-module change → `sonnet`. Leave it off rather than guess.

Behavioral discipline: `### Outcomes` / `### Goal` / `### Invariants` state observable properties only, with no project-specific file or symbol names (normative names from a spec or `CLAUDE.md` are fine). If design work would be free to pick a different symbol, the name is `/task:to-plan`'s call, not this file's.

Before saving, self-check and fix inline (drafting hygiene; step 5 is the post-save pass):

1. Every fork raised in the brainstorm has a home in some phase, or an explicit `## Out of scope` mention.
2. Each `**Ready description:**` stands alone — a reader who hasn't seen the roadmap could pick it up in `/task:to-plan` from the blockquote alone.
3. No placeholders (`TBD`, `TODO`, `???`, `fill in`).
4. Every `**Dependencies:**` cites a task number that exists in this file.
5. Every item heading produces a unique kebab-case slug.
6. Item numbers unique across the whole file — the driver's auto-mark keys on the number, so two items sharing one would be ticked together.
7. Every confirmed decision (step 2) has a concrete home, or was explicitly dropped with a stated reason.
8. Every cross-artifact reference is a Markdown link — `Spec:` headers, `### Spec references` citations, `## Prerequisites`, `## Backlinks`.

### 4. Save

Write the file directly — no in-chat preview, no confirmation prompt.

1. Slug: kebab-case from the initiative title, ≤ 50 chars (`add-auth-flow`, `migrate-to-vite`).
2. **Slug collision.** If that slug is already in the caller's `ROADMAPS:` list → **stop** and pose an `AskUserQuestion` (**Overwrite** / **Pick different slug**). Never silently overwrite. That list is a snapshot taken before the brainstorm rounds, and unlike the task captures there is no writer script to refuse a collision here — so when the slug is *absent* from it, confirm with a file read that nothing is there before writing.
3. Write `$AI_DIR/roadmap/<slug>.md` (creating the directory if needed) with the full content, `Spec:` headers included. Nothing else is written — spec authorship is `to-spec`'s.
4. Validate it: `bash "${CLAUDE_PLUGIN_ROOT}/skills/validate/validate.sh" roadmap <slug>` — surface any WARN/ERROR in the caller's digest; only a setup-precondition failure (exit 2) hard-stops.

### 5. Light self-check (report-only)

Skim the **saved file** (not the in-chat draft) yourself — no subagent fanout, no lens-audit machinery — against three lenses:

- **Coverage** — phase and fork coverage, dependency integrity (dangling or cyclic).
- **Decomposition** — any item reading as compound: two unrelated concerns, or far more outcomes than its neighbours.
- **Clarity** — behavioral discipline held, descriptions self-contained, and each `### Spec references` citation naming a `Spec:`-referenced `$AI_DIR/spec/<spec-slug>.md` that really has that `§N`, with a target matching its label (a copied citation pointing at the previous spec still resolves for an agent and misleads the human).

Report a count per lens plus the obvious issues, a few lines, in the caller's digest. **Never rewrite the saved file** — findings are for the user to fix or discuss; there is no auto-apply.

## Forbidden

Binding on every roadmap this flow writes:

- Naming project-specific files, modules, functions, types, or constants in `### Outcomes` / `### Goal` / `### Invariants` — normative names from spec/CLAUDE.md are the only exception.
- Planning implementation details (file lists with line numbers, function signatures, code blocks > 5 lines) — that is `/task:to-plan`'s job when the item is picked up.
- Modifying any file other than `.task/roadmap/<slug>.md` — specs live at `.task/spec/<slug>.md` and are authored only by `to-spec`, never written or edited here.
- Auto-checking / auto-unchecking item checkboxes — ticking `- [x]` happens inside the executing session (or, in a roadmap run, the `roadmap-to-workflow` **driver**), never here and never inside a per-item agent.
- A single-direction monologue in a decomposition round — offer ≥ 2 options or explicitly justify why only one is viable. (The Decision Inventory and the cold-start recap are chat-only recaps, not decomposition rounds — exempt.)
- Generic risks ("watch out for bugs") — risks must be specific to the initiative and project.
- More than one initiative per file — split and pick one for this run.
- Persisting topics the user asked to skip; placeholders anywhere.
- Writing a `.refine.md` sidecar, a `.spec.md` sidecar, or a `.lock` file — none of those exists in the pipeline.
