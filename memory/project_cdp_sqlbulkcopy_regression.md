---
name: project-cdp-sqlbulkcopy-regression
description: 26R2P User CRUD write regression traced to CDP PR 23080 SqlBulkCopy change by Josh Machol
metadata: 
  node_type: memory
  type: project
  originSessionId: f7bb6b64-8c01-406c-8520-96a485034a41
---

User CRUD interactive writes (Create/Update) are ~20% slower in 26R2P vs 26R1. Delete with rules is ~58% slower.

**Root cause:** CDP PR 23080 "CPTI: Make Record Updates Fast" (Josh Machol, merged 2026-05-09) switched record saves to use `SqlBulkCopy` to load input data. This delivers 80% improvement for bulk operations (20K+ records) but adds fixed per-call overhead that hurts single-record interactive CRUD.

**Files changed:** `DataAccessService.cs`, `DatabaseObjectServices.cs`, `SqlQueryBuilder.cs`, `Utilities.DQ/Evaluator.cs`, `JsonSettings.cs`

**Recommended fix:** Gate the `SqlBulkCopy` path behind a record count threshold (e.g., 10+ records); fall back to parameterized INSERT for single-record calls.

**Why:** Bulk operations amortize SqlBulkCopy setup cost; single-record calls pay the full setup on every request.

**How to apply:** If user asks about User CRUD perf regression in 26R2P, or about the CDP SqlBulkCopy change — this is the known cause and fix direction. Raise with Josh Machol.
