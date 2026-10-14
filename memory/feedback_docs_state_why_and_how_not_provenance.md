---
name: feedback_docs_state_why_and_how_not_provenance
description: Plans, design pages, board rows and code comments state the reason and the mechanism, never who asked, when, or the dialog that produced a decision
metadata:
  type: feedback
---
Design docs, plans, board row text and comments carry no person references ("Gene 18:49", "lead", "agreed 17:33"), no Q&A transcripts and no "answered / took the recommendation" history. Each decision is restated as **what** it is, **why** (the reason that makes it right), and **how** it works.

**Why:** a reader later needs to understand the reason behind a decision and the mechanism, not the conversation that produced it. Provenance lines age into noise and hide the reasoning.

**How to apply:**
- Write a decision as "Decision / Why / How".
- Turn open-question tables into decisions once answered.
- Remove timestamps and names from design text.
- Keep provenance only where a record's purpose is audit (row records, ledger, `_decisions.md` entries are still factual logs, but phrase their reasons as why/how too).
- Related: [[feedback_value_picker_always]].
