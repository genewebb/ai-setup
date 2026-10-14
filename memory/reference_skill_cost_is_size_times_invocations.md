---
name: reference_skill_cost_is_size_times_invocations
description: "A skill body's real cost is body_tokens x turns_it_stays_resident, not body size — measure invocation frequency from transcripts before splitting"
metadata: 
  node_type: memory
  type: reference
  originSessionId: ef7d1507-9389-4274-b379-610fa13e50c5
  modified: 2026-08-01T21:54:27.067Z
---

A skill's **body** only loads when the `Skill` tool actually invokes it, then rides along
in context for every remaining turn. Real cost is `body_tokens × turns_after_invocation`.
Body size alone says nothing.

Measured 2026-08-01 over 189 transcripts / 7 days: **56 `Skill` calls across 32 skills.**
The two largest bodies in the corpus — `testauto-multistep-steps` (18,139 tok) and
`testauto-matching-scenarios` (13,950 tok) — were invoked **zero times all week**. Only
`crewchief-remote-box-prep` (3 calls, 588 turns resident) and `crewchief-web-ui` (2 calls,
160 turns) cost anything at all.

This made the [[project_skill_body_splits_2026-08-01]] payoff ~1M tok per 48h instead of
the forecast 30-60M — a 30-50x error that came from measuring size carefully and assuming
frequency. Same failure shape as the description-trim mis-measurement in
[[project_skill_description_trim_2026-08-01]], one level up.

**How to apply:** before splitting or trimming any skill for cost reasons, run
`skill-invocation-frequency.ps1` (section 9 of `03 Shared\AICosts\ReducePromptCost.md`) —
it counts `tool_use` blocks with `name == 'Skill'` in `~/.claude/projects/**/*.jsonl` and
reports turns-after per skill. Rank by `body_tokens × turns_after`. A 17k-token body that
fires twice a year is not a cost problem. Descriptions are the opposite case — always
loaded, so size *is* cost there.
