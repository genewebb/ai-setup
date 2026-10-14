---
name: project_connect_import_sequence_race
description: Connect multi-thread bulk import silently drops whole 1000-record blocks via an ID-sequence allocation race
metadata: 
  node_type: memory
  type: project
  originSessionId: 798ce0d1-df00-4578-839a-23f12e5ea747
---

Connect bulk import (Profisee 26R2PV2) silently loses whole 1,000-record blocks under parallel workers. Found reviewing workflow execution 10000150 (template 10000145, *Matching Workflow Connect Testing v2*): 97,000 of 100,000 source `RetailClient100K` rows imported. The missing 3,000 were three contiguous 1,000-blocks, all in Source System 1 (codes 100000000-999, 100003000-999, 100006000-999) — **block loss, not scattered record rejection**.

Root cause: Connect allocates ID/code blocks with a non-atomic `SELECT current_value FROM sys.sequences ... ; ALTER SEQUENCE [data].[s<Entity>] RESTART WITH <next>`, run across all 12 worker threads (`connex.tServiceProvider` → `WorkerQueueOptions.WorkerCount`, set by the "Set Connect Number of Threads" step). At cold start all workers race the freshly-created sequence; 3 `SELECT current_value` reads errored (`Profisee.logging.tSystemLog`, Level=Error, 15:39:06.230) and the `RESTART WITH` values came through **non-monotonic** (8000→6000→9000 = workers clobbering each other). Each errored allocation = one 1,000-block dropped. **Batch-level failures are NOT propagated — the job reports success.**

**Why:** silent 3% data loss flows straight into the downstream matching run and contaminates all metrics; the run looks "done."

**How to apply:** Diagnose by bucketing imported entity Codes by 1000 to spot whole-block gaps, then confirm against `logging.tSystemLog` sequence RESTART errors in the import window. Mitigate by pre-warming the entity sequence single-threaded before the parallel import, or lowering WorkerCount for initial load. Best fix in the workflow = add a post-import verification step (target count vs source count, fail on mismatch). Platform-level: Connect's read+`ALTER SEQUENCE RESTART` allocator is not concurrency-safe (should use `sp_sequence_get_range`). Related: [[reference_profisee_platform_log]], [[project_cdp_sqlbulkcopy_regression]], [[reference_scenariomgt_db]].
