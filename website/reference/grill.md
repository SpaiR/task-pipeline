# grill

Pre-capture interrogation. Pressure-tests a plan or decision **before** it's frozen into an artifact, then routes to the right capture skill. Writes nothing, touches nothing under `.task/`.

See the [grill guide](/guide/grill) for the full walkthrough.

## Usage

```text
/task:grill [<context>]
```

**Input** — `$ARGUMENTS`, optional. A topic or free-form context to grill (`"the retry design"`, `"whether to shard the queue"`). Empty → grills the plan being discussed in the current chat.

## What it does

- Frames the target in a sentence or two.
- Resolves *facts* itself (from the codebase) and spends questions only on genuine *decisions*.
- Grills one `AskUserQuestion` fork at a time — each with 2–4 concrete options and an honest recommendation.
- Keeps a decision ledger: `{the decision} — because {the reason}`.
- Ends with a pre-mortem kill-shot question, then prints the full ledger.

Typical depth is 3–7 questions.

## Config

**No config gate, no setup.** `grill` is the one skill that neither reads nor writes anything under `.task/` — it runs in a fresh, unconfigured project. Dialog mirrors the language of your chat.

## Output

A decision ledger printed as chat text (there is no file), followed by a routing footer naming exactly one next skill:

```text
## Decision ledger
1. {decision at full specificity} — because {the load-bearing reason}
2. …

→ Next: /task:to-plan — one task with the approach nailed down; capture Description + Plan.
```

## Does not

- Write any file, anywhere — serializing the ledger is the `to-*` skills' job.
- Batch questions — one fork per prompt, always.
- Implement, refactor, or "just fix it" mid-grill.
- Agree by reflex — if your leaning is the weaker call, the recommendation says so.
