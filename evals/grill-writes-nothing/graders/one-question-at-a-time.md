---
type: llm
criteria: |
  The reply asks the user exactly ONE question, not a batch of them, and that
  question attacks a load-bearing weakness of the proposal (unbounded memory
  growth, staleness after a write, or cache-key correctness) rather than asking
  for detail the user already gave.
focus: the question being asked
---
grill interrogates one question at a time; a questionnaire defeats the point.
