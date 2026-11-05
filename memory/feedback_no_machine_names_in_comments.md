---
name: feedback-no-machine-names-in-comments
description: "Keep machine names (CORPLTR94, SMVM*, etc.) out of comments, descriptions and workload text unless required; machine values belong in reference data"
metadata:
  node_type: memory
  type: feedback
  originSessionId: 8ecc9a58-e238-47c7-875f-417dfa1ed23f
  modified: 2026-11-05T15:16:43.273Z
---

Do not put machine names in code comments, step/workload descriptions or file notes unless they are actually required.

**Why:** Gene, 11/05/2026: "also do not put machine names in comments if not required". Workloads and code must stay box-neutral so the same pack runs from Gene's machine to production.

**How to apply:** In CrewChief packs, machine values go only in `reference-kv/<family>/machines.json` (and similar sets); descriptions say "this instance" / "the machine's API user". Same for C# comments. Related: [[feedback_centralize_constants]].
