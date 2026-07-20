# Grill before you capture

[`/task:grill`](/reference/grill) is the optional pre-capture step. It sits at the very first stage of the pipeline — "discuss freely in chat" — and gives that discussion teeth. It interrogates a plan or decision one question at a time, keeps a running ledger of what you decided and why, ends with a pre-mortem, then routes you to the right capture skill.

It writes **nothing**. Its whole output is a hardened discussion plus a decision ledger that a `to-*` skill then serializes.

## Why grill before you capture

A capture skill freezes a discussion into a file. If the discussion was fuzzy, the file is fuzzy. `grill` is where you pressure-test the thinking *before* it's frozen — so `to-plan` / `to-spec` / `to-task` / `to-roadmap` serialize something that's already been examined.

## Where it comes from

`grill` descends from Matt Pocock's [grill-me](https://github.com/mattpocock/skills) — the interrogate-before-you-build idea that made the case interrogation belongs before code. This one adds a decision ledger, recommendations that are allowed to disagree with you rather than rubber-stamp, a closing pre-mortem, and routing into capture — the part grill-me leaves open: somewhere to put the answers.

## How it works

```text
/task:grill the retry design
```

1. **It frames the target** — states, in a sentence or two, the decision it's about to attack.
2. **It resolves facts itself.** Anything the codebase can answer — what a file does, whether a library is already a dependency — it looks up with plain tools. It spends questions only on genuine decisions.
3. **It grills, one question at a time.** Each question is a real fork with 2–4 concrete options and a recommendation. The first chip is its honest recommended answer — and if your leaning looks like the weaker call, the recommendation will say so rather than agree by reflex.
4. **It keeps a ledger.** After each answer it echoes one new line: `{the decision} — because {the reason}`.
5. **It ends with a pre-mortem** — one kill-shot question, like *"this shipped and failed; what was the cause?"* — and folds the answer into the ledger.
6. **It prints the full ledger** and routes you onward.

A typical grill is 3–7 questions. It chases the one answer that would change everything, not ten that wouldn't.

## No config needed

`grill` is the one skill that neither reads nor writes anything under `.task/` — `config.md` included. It runs in a fresh, unconfigured project, before any capture exists. Its dialog mirrors the language of your chat.

## Where it routes you

When the interrogation is done, `grill` diagnoses what you actually grilled and points at exactly one next skill:

| What the ledger turned out to be | Routes to |
|---|---|
| Load-bearing "we chose X over Y because…" technical reasoning | [`/task:to-spec`](/guide/specs) |
| One task, approach settled | [`/task:to-plan`](/guide/single-task) |
| One task, approach still open | [`/task:to-task`](/guide/single-task) |
| An initiative that sprawled into several tasks | [`/task:to-roadmap`](/guide/roadmaps) |

It doesn't run the capture skill for you — the footer is the handoff. You review the ledger, then run the suggested command.

→ Next: [Roadmaps](/guide/roadmaps) — capturing a multi-task initiative.
