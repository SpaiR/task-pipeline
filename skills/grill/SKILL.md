---
name: grill
description: 'Interrogate a plan, decision, or idea one question at a time before it is captured — stress-test the weak spots, keep a decision-plus-rationale ledger, end with a pre-mortem, then route to the right capture skill. Writes no artifacts; hardens the chat discussion so `to-spec` / `to-plan` / `to-task` / `to-roadmap` capture something already examined. Use it when a decision feels under-examined and you want it pressure-tested before you freeze it.'
disable-model-invocation: true
user-invocable: true
---

Pressure-test a plan, decision, or idea **before** it is frozen into an artifact. `grill` sits at the pipeline's first stage — "discuss freely in chat" — and gives that stage teeth: it interrogates the thinking one question at a time, records every answer as a decision with its rationale, closes with a pre-mortem, then hands off to the right capture skill. It is the pre-capture step, not a capture step: it writes **nothing**. Its output is a hardened discussion plus a decision ledger that a `to-*` skill then serializes.

Adapted from mattpocock/skills' `grilling`. Kept from the original: **one question at a time**; facts are looked up in the environment, only genuine decisions are asked; no acting on the plan until shared understanding is confirmed. Added here: a decision ledger, smart exit routing, an anti-sycophancy rule, and a pre-mortem finale.

**Input:** `$ARGUMENTS` — optional. A topic or free-form context to grill (e.g. "the retry design", "whether to shard the queue"). Empty → grill the plan/decision being discussed in the current chat.

**No config gate, no setup.** Unlike every `to-*` skill, `grill` neither checks `.task/config/config.md` nor runs inline setup — it touches nothing under `.task/` and can run in a fresh, unconfigured project before any capture exists. Follow `config.md` → Language for dialog only if a config happens to exist; otherwise mirror the language of the discussion.

## Instructions

### Step 1: Frame what is being grilled

State, in 1–3 sentences, the plan/decision/idea as you currently understand it — from `$ARGUMENTS` if given, else from the chat. This is the target the questions attack. Do not ask the user to confirm the framing with a separate prompt; the first question implicitly tests it.

### Step 2: Separate facts from decisions

Before asking anything, split what you need into two piles:

- **Facts** — anything the environment can answer: what a file does, whether a library is already a dependency, how an existing flow behaves, what the config says. **Look these up yourself** (Read / Grep / Glob / Bash per `config.md` → Code Navigation when a config exists, plain tools otherwise). Never ask the user a question the repo already answers.
- **Decisions** — genuine choices with trade-offs, no single right answer derivable from the environment. **These, and only these, are what you ask.**

If a supposed decision turns out to have a factual answer, resolve it silently and move on — don't burn a question on it.

**Nothing to grill.** If, after this split, no genuine decision is left — every fork is already settled, or all of it is factual and answerable from the environment — **stop**. Do not manufacture questions to justify running. Say so plainly and redirect straight to the fitting capture skill (Step 7's routing), e.g. `→ Next: /task:to-plan — nothing left to interrogate; the approach is settled, capture it.`

### Step 3: Grill — one question at a time

Walk the decision tree, **one `AskUserQuestion` per genuine fork** (convention (c)). Never batch. After each answer, new forks it exposes become later questions.

Each question:

- Poses a real decision with 2–4 concrete options.
- **Carries a recommendation.** The first chip is your recommended answer, labelled `… (Recommended)`. Each option's `description` states its consequence — what you get and what it costs — so the choice is informed, not blind.
- **Anti-sycophancy rule.** The recommendation is your honest read, not an echo of where the user seems to be leaning. When the user's implied leaning looks wrong, the recommended chip **must be the disagreement**, and its description must say why the leaning is the weaker call. Agreeing by reflex is a failure of this skill.

Keep going until the forks that matter are resolved. Depth over breadth — chase the one answer that would change everything, not ten that wouldn't.

### Step 4: Maintain the decision ledger

After every answered question, append one line to a running ledger, kept in chat (never written to a file):

```
## Decision ledger

1. {the decision, at full specificity} — because {the load-bearing reason}
2. {…}
```

This ledger is the raw material `to-spec` (or another capture skill) will serialize. Keep each line concrete enough that a reader who missed the chat understands both the choice and why it was made.

### Step 5: Pre-mortem finale

Once the branches are resolved, ask **one** kill-shot question via `AskUserQuestion` before the final confirmation — pick whichever bites harder:

- "Fast-forward: this shipped and failed. What was the cause?" — options being the most plausible failure modes you see, recommended chip = the one you judge most likely.
- "What would make this whole thing unnecessary?" — options being the simpler alternatives or the do-nothing case.

Fold the answer into the ledger as a final decision line (the mitigation, or the confirmed reason to proceed anyway).

### Step 6: Confirm the ledger

Reprint the full ledger, then pose one `AskUserQuestion` (convention (b)) with chips **Accept** / **Edit** / **Decline**:

- **Accept** → proceed to Step 7 (routing).
- **Edit** → focused follow-up on what to add, correct, or drop; re-print the ledger; repeat until accepted.
- **Decline** → write nothing and stop with `nothing captured — re-run /task:grill when you want to re-open the decision`. (Correcting a ledger line is **Edit**; a Decline ends the grill.)

### Step 7: Route to the right capture skill

Diagnose what was actually grilled and close with the canonical footer (convention (a), flag-free) naming **exactly one** next skill plus a one-line reason:

- **Pinned technical decisions** — the ledger is load-bearing "we chose X over Y because…" reasoning that must survive re-derivation → `→ Next: /task:to-spec — the ledger is load-bearing technical reasoning; pin it as a spec.`
- **A single implementable task, approach settled** → `→ Next: /task:to-plan — one task with the approach nailed down; capture Description + Plan.`
- **A single task, approach still open** → `→ Next: /task:to-task — one task worth recording now; flesh out the plan later.`
- **An initiative that sprawled into several tasks** → `→ Next: /task:to-roadmap — this grew into a multi-task initiative; capture it as a roadmap.`

Pick the one that fits; state the reason in the same language as the dialog. Do not run the capture skill yourself — the footer is the handoff.

## Forbidden

- **Writing anything, anywhere** — no files, no edits, above all nothing under `.task/`. Serializing the ledger is the `to-*` skills' job; `grill` only hardens the discussion.
- **Batching questions** — one `AskUserQuestion` per fork, always. No multi-question rounds.
- **A config gate or inline setup** — `grill` never checks or creates `config.md` and never touches `.task/`.
- **Acting on the grilled plan** — no implementing, refactoring, or "just fixing it" mid-grill. This skill interrogates; it does not execute.
- **Asking what the environment can answer** — resolve facts by looking them up; spend questions only on genuine decisions.
- **Reflexive agreement** — a recommendation that merely mirrors the user's leaning when that leaning is the weaker call violates the anti-sycophancy rule.
