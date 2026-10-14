---
name: skillmodelanddatareview
description: SkillModelAndDataReview (Profisee model/data compare) — disk-first micro-batching, resume from dated report JSON, known noise filters, user- MCP prefix
metadata:
  type: reference
---

**SkillModelAndDataReview** (local vs target Profisee model/data compare): skill at `C:\devopslocal\Documentation\speed-merchants\skills\SkillModelAndDataReview.md`; default report path and Step 3 batch size (25 entities per chunk) are in that file's Configuration.

- Drive the **same dated report file** to the skill's success criteria (Step 3 → 4 → 5) using **disk-first micro-batching**: after each micro-batch of MCP calls, update the report including `## Run state (Step 3 — machine-readable)` (`step3_entities_compared_count`, `step3_next_entity_to_compare`, `step3_complete`). Runs span multiple turns; the next turn **reads that file** and continues. Never treat "say continue" as a substitute for persisted progress; never imply the run is finished while `step3_complete` is false without labeling paused/blocked. Only stop early for a documented hard failure.
- MCP hosts often expose Profisee servers with a `user-` prefix (e.g. `user-speedMcpLocal`); call tools using the names actually registered, but report text may use logical labels.
- Attribute-mismatch noise filter: DateTime/Date `data_type_information` 0 vs 250 are equivalent — ignore; still report real structural differences (attributes missing on one side).
- If Profisee admin UI and MCP/REST metadata disagree for the same hub URL, first confirm the MCP endpoint matches that hub; if it does, treat persistent gaps as metadata propagation / platform behavior to investigate, not wrong-environment mapping.

(Migrated from myworkspace AGENTS.md, 2026-07-30.)
