---
name: feedback-reviews-by-claude-clean-session
description: "Requirements independent review = Claude Code in a CLEAN session (fresh session, review prompt only), NOT Copilot/Codex/Grok; since 2026-09-26 (Q0-68) a fresh-context subagent also counts; review entry `given` must say 'clean session' (validator enforces) — Gene 2026-09-23"
metadata:
  node_type: memory
  type: feedback
  originSessionId: 0a36bc9c-d39a-4732-ac46-792b6bc2e0b4
  modified: 2026-09-24T00:35:07.435Z
---

Gene 2026-09-23 20:31: "We will not be using copilot for reviews; we will start a clean session and use Claude."

**Rule:** the independent reviewer of a requirements revision is Gene, or Claude Code in a clean session: a fresh session that gets `review/REVIEW-PROMPT.md` and nothing else, never the session that authored the revision. Copilot/Codex/Grok are not used for reviews.

**Why:** the one Copilot round (WVC corpus, 9/23) worked but Gene wants one tool; a clean Claude session has no authoring context, which is the independence that matters.

**How to apply:**
- Standard changed: `RequirementDesign.md` approval sequence step 2 (speedy corpus) and the requirements-writing skill say clean session, same tool allowed.
- `reqtools.py` (speedmerchants, uncommitted 9/23): on a live artifact `kind: tool` reviews must have `tool: Claude` (any other tool = error), and a Claude review needs the words "clean session" in `given`; every review entry starts `given` with "clean session: ...". (A second editor extended my check mid-session to "Claude only"; kept.)
- The Copilot review entries were REMOVED from the WVC YAMLs (they fail the new rule); `review/INDEPENDENT-REVIEW-copilot-2026-09-23.md` stays as the record of that round.
- The authoring session never writes the review itself; it prepares the prompt, tells Gene to open a new session, and applies the findings afterwards. See [[project_workflow_vs_code_corpus]].

**Update 2026-09-26 (Gene, Q0-68, tracker one-goal programme):** a fresh-context subagent (Agent tool) given only the review prompt counts as the clean-session reviewer, so one goal run can author and have reviews done without /clear between steps. `given` says "clean session (fresh subagent, Q0-68)". The authoring main context still never reviews its own output.
