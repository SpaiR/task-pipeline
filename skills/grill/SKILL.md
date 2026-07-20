---
name: grill
description: Interrogate a plan or decision one question at a time before capture, keeping a decision-plus-rationale ledger, then route to the right capture skill.
disable-model-invocation: true
user-invocable: true
---

Pressure-test a plan, decision, or idea **before** it is frozen into an artifact. `grill` sits at the pipeline's first stage — "discuss freely in chat" — and gives it teeth: it interrogates the thinking one question at a time, records every answer as a decision with its rationale, closes with a pre-mortem, then hands off to the right capture skill. It writes **nothing**; its output is a hardened discussion plus a decision ledger that a `to-*` skill then serializes.

**Input:** `$ARGUMENTS` — optional. A topic or free-form context to grill (e.g. "the retry design", "whether to shard the queue"). Empty → grill the plan/decision being discussed in the current chat.

**No config gate, no setup.** `grill` reads nothing under `.task/` — `config.md` included — so it runs in a fresh, unconfigured project before any capture exists. Dialog mirrors the language of the chat; facts are looked up with plain tools (Read / Grep / Glob / Bash).

### Step 1: Frame what is being grilled

State, in 1–3 sentences, the plan/decision/idea as you currently understand it — from `$ARGUMENTS` if given, else from the chat. This is the target the questions attack. Do not ask the user to confirm the framing with a separate prompt; the first question implicitly tests it.

### Step 2: Resolve facts lazily, ask only decisions

Split what stands between you and the **next** question into two piles:

- **Facts** — anything the environment can answer: what a file does, whether a library is already a dependency, how an existing flow behaves. **Look these up yourself** with Read / Grep / Glob / Bash. Never ask the user a question the repo already answers.
- **Decisions** — genuine choices with trade-offs, no single right answer derivable from the environment. **These, and only these, are what you ask.**

Resolve facts **lazily** — only the ones that gate the next question, not everything up front — so the first question reaches the user fast. When several independent reads are needed for one question, batch them in parallel. If a supposed decision turns out to have a factual answer, resolve it silently and move on — don't burn a question on it.

**Nothing to grill.** If no genuine decision is left — every fork is already settled, or all of it is factual and answerable from the environment — **stop**. Do not manufacture questions to justify running. Say so plainly and redirect straight to the fitting capture skill (Step 7's routing), e.g. `→ Next: /task:to-plan — nothing left to interrogate; the approach is settled, capture it.`

### Step 3: Grill — one question at a time

Walk the decision tree, **one `AskUserQuestion` per genuine fork** (convention (c)). Never batch. After each answer, new forks it exposes become later questions.

Each question:

- Poses a real decision with 2–4 concrete options.
- **Carries a recommendation.** The first chip is your recommended answer, labelled `… (Recommended)`. Each option's `description` states its consequence — what you get and what it costs — so the choice is informed, not blind.
- **Anti-sycophancy rule.** The recommendation is your honest read, not an echo of where the user seems to be leaning. When the user's implied leaning looks wrong, the recommended chip **must be the disagreement**, and its description must say why the leaning is the weaker call. Agreeing by reflex is a failure of this skill.

**Depth budget.** A typical grill is 3–7 questions. Depth over breadth — chase the one answer that would change everything, not ten that wouldn't. Stop as soon as the remaining forks would not change what gets captured.

### Step 4: Maintain the decision ledger

Maintain a ledger internally — one line per answered question, in the form `{the decision, at full specificity} — because {the load-bearing reason}`. After each answer, echo only the **new** line, not the whole ledger. Keep each line concrete enough that a reader who missed the chat understands both the choice and why it was made. The full block is printed once, in Step 6.

### Step 5: Pre-mortem finale

Once the branches are resolved, ask **one** kill-shot question via `AskUserQuestion` before printing the ledger — pick whichever bites harder:

- "Fast-forward: this shipped and failed. What was the cause?" — options being the most plausible failure modes you see, recommended chip = the one you judge most likely.
- "What would make this whole thing unnecessary?" — options being the simpler alternatives or the do-nothing case.

Fold the answer into the ledger as a final decision line (the mitigation, or the confirmed reason to proceed anyway).

### Step 6: Print the ledger

Once the pre-mortem answer is folded in, process the whole set of answers together and print the full ledger **as message text in your reply** — the whole block, once (convention (b)):

```
## Decision ledger

1. {the decision, at full specificity} — because {the load-bearing reason}
2. {…}
```

The ledger **is** the grill's output — print it, then go straight to Step 7 routing, no confirmation chip: every line restates a decision the user already made through the questions above.

grill writes nothing, so there is no file to guard and no "declined" state — an abandoned grill is simply one the user doesn't route onward. If the user wants a line changed, they say so in chat: correct it and reprint the ledger.

### Step 7: Route to the right capture skill

Diagnose what was actually grilled and close with the canonical footer (convention (a), flag-free) naming **exactly one** next skill plus a one-line reason:

- **Pinned technical decisions** — the ledger is load-bearing "we chose X over Y because…" reasoning that must survive re-derivation → `→ Next: /task:to-spec — the ledger is load-bearing technical reasoning; pin it as a spec.`
- **A single implementable task, approach settled** → `→ Next: /task:to-plan — one task with the approach nailed down; capture Description + Plan.`
- **A single task, approach still open** → `→ Next: /task:to-task — one task worth recording now; flesh out the plan later.`
- **An initiative that sprawled into several tasks** → `→ Next: /task:to-roadmap — this grew into a multi-task initiative; capture it as a roadmap.`

Pick the one that fits; state the reason in the same language as the dialog. Do not run the capture skill yourself — the footer is the handoff.

## Forbidden

- **Writing anything, anywhere** — no files, no edits, above all nothing under `.task/`. Serializing the ledger is the `to-*` skills' job; `grill` only hardens the discussion.
- **Reading or writing anything under `.task/`, `config.md` included** — no config gate, no inline setup; `grill` runs before any config exists and dialog mirrors the chat's language.
- **Batching questions** — one `AskUserQuestion` per fork, always. No multi-question rounds.
- **Acting on the grilled plan** — no implementing, refactoring, or "just fixing it" mid-grill. This skill interrogates; it does not execute.
- **Asking what the environment can answer** — resolve facts by looking them up; spend questions only on genuine decisions.
- **Reflexive agreement** — a recommendation that merely mirrors the user's leaning when that leaning is the weaker call violates the anti-sycophancy rule.
