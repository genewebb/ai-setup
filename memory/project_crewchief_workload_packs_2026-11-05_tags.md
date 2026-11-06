---
name: project-crewchief-packs-tags-2026-11-05
description: 11/05 Connect pack tags 1K/1M + 4T/8T/12T and TestAutoTags ensure in upsert steps; PROD tags added; not restored on TR2 (Connect closed 11/06, reaches next box)
metadata:
  node_type: memory
  type: project
  originSessionId: 8ecc9a58-e238-47c7-875f-417dfa1ed23f
  modified: 2026-11-06T16:45:42.154Z
---

11/05 17:30: Connect pack status after the tags rule ([[feedback-tags-must-exist-in-testautotags]]; Code = Name = tag text). Connect pack (uncommitted, lint PASS):
CrewChief workload tags renamed 1k/1m/t4/t8/t12 -> 1K/1M/4T/8T/12T; tests masters, provider -all parents, schedules got all three thread tags; 54 upsert steps now add missing TestAutoTags.
PROD already fixed by a one-off local CLI run: Connect, 1K, 1M, 4T, 8T, 12T + 54 AUTO:SMVMTR2:26R2:* tags added (157 tags total; matching session added its own).

**Why:** the rule and the missing-tag check live in [[feedback-tags-must-exist-in-testautotags]]; this file is only the Connect pack's status.
**How to apply:** 11/06: the 26R2 round ended and Gene closed Connect testing out; SMVMTR2 was NOT re-restored. The tag edits reach the next box (26R4) with its pack restore ([[project-pack-docs-in-app-help-2026-11-06]]). Matching follow-up prompt: Q:\Work\Work\99 Documentation\Connect\05 Prompt - Matching Tags (Size, Threads, TestAutoTags).md. Related: [[project_crewchief_workload_packs_2026-11-04]].
