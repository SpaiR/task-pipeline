---
paths:
  - "skills/_lib/roadmap-driver.js"
---

# Editing the roadmap driver

The full contract is `docs/contract.md` § `roadmap-to-workflow` execution shape (driver contract).

- **Read the `workflow-authoring` skill first** before changing how the script uses `agent()`, `parallel()`, `phase()` or `log()`.
- **Sandbox limits.** The script has no filesystem or Node.js APIs, so every write happens inside an `agent()` stage. `Date.now()`, `Math.random()` and an argless `new Date()` throw, because they would break resume. `meta` must stay a pure literal.
- **It is reached by its registered name**, `task:roadmap-driver`: the manifest's `name` plus this file's `meta.name`, declared under the manifest's `"workflows"` key. Renaming either half moves the roadmap-to-workflow skill's invocation and `tests/driver-registration.test.sh` with it.
- **An `args` change moves three places together:** the up-front assertions in this file, the args the roadmap-to-workflow skill builds in its step 2, and the contract's description of them.
- **Keep the `pure` block self-contained.** Everything between `// --- pure (` and `// --- end pure` — the `STAGES` table and every function that needs no Workflow global — is extracted verbatim by `t_driver_pure` in `tests/lib.sh` and run alone under `node` by the `tests/driver-*.test.sh` cases. Nothing in it may read the `args` global or call `agent()`, `parallel()` or `log()`. A new pure helper goes inside the block and gets its cases in the matching test.
- **Digest shapes are parsed.** The plan stage's `OK #N <item-slug> planned`, the implement and review stages' `OK|FAIL #N <item-slug> <summary>` and the review's `MARK-OK #N` are asserted before use. Change one together with `skills/_lib/plan-driver.md` § Driver mode or `agents/code-reviewer.md`, and the tests.
- **Labels, phase names and `agent()` options are part of the resume cache.** Changing them invalidates `resumeFromRunId` for runs started on the older script.
- **Ship a test with the change**, as for any helper: a case in the matching `tests/driver-*.test.sh`, with the suite green. Those cases need `node`; without it they print SKIP.
