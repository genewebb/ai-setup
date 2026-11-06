---
name: project-crewchief-packs-tags-2026-11-05
description: 11/05 Connect pack tags 1K/1M + 4T/8T/12T and TestAutoTags ensure in upsert steps; PROD tags added; TR2 restore pending
metadata:
  node_type: memory
  type: project
  originSessionId: 8ecc9a58-e238-47c7-875f-417dfa1ed23f
  modified: 2026-11-05T23:44:54.690Z
---

11/05 17:30: Connect pack status after the tags rule ([[feedback-tags-must-exist-in-testautotags]]; Code = Name = tag text). Connect pack (uncommitted, lint PASS):
CrewChief workload tags renamed 1k/1m/t4/t8/t12 -> 1K/1M/4T/8T/12T; tests masters, provider -all parents, schedules got all three thread tags; 54 upsert steps now add missing TestAutoTags.
PROD already fixed by a one-off local CLI run: Connect, 1K, 1M, 4T, 8T, 12T + 54 AUTO:SMVMTR2:26R2:* tags added (157 tags total; matching session added its own).

**Why:** the rule and the missing-tag check live in [[feedback-tags-must-exist-in-testautotags]]; this file is only the Connect pack's status.
**How to apply:** pack zip + Replace restore of workloads/connect on SMVMTR2 only after the 26R2 round ends (Gene). Matching follow-up prompt: Q:\Work\Work\99 Documentation\Connect\05 Prompt - Matching Tags (Size, Threads, TestAutoTags).md. Related: [[project_crewchief_workload_packs_2026-11-04]].
