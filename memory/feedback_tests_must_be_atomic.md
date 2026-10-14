---
name: feedback-tests-must-be-atomic
description: "Every test must be atomic — self-contained, order-independent, self-provisioning, self-cleaning"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 8109969f-a9a3-49ba-a7b5-e9391c1e42a4
---

All tests (unit AND integration) MUST be atomic: runnable in isolation, in any order, repeatably, with no dependence on data left by other tests or on pre-existing instance/environment state, and leaving no state behind.

**Why:** non-atomic tests are exactly what caused the integration suite's cascading failures — leaked entities (182 debris) corrupted the shared `CdpService` cache, parallel runs raced, and tests that read "the latest"/"an existing" record got another test's data. Atomicity removes ordering coupling, flakiness, and shared-state corruption at the source.

**How to apply:**
- Each test ARRANGEs its own prerequisites (create the records/config/strategy it needs) and TEARS them down in cleanup that runs even on partial setup failure (MSTest skips `[TestCleanup]` when `[TestInitialize]` throws — so self-clean inside Setup's try/catch too). See [[project_workloadexecution_cleanup]] patterns.
- Never depend on a pre-existing strategy/config/record or on `KnownStrategyName`-style external data. "Discover an existing X then act on it" is NOT atomic — create X first, or the test must self-provision it.
- Model SCHEMA (entities/attributes) may be assumed to exist (provision once, e.g. [[project_metadata_model_import]]); test RECORDS must be created/deleted per test.
- Make writes idempotent: pre-delete by unique key (e.g. ConnEx config name via `?ConfigurationUids=` DELETE) so a leftover from a crashed prior run can't 409.
- Mutating classes that hit a shared live model run `[DoNotParallelize]` so they don't race readers (CdpService..ctor reloads the model cache).
- Relates to [[feedback_scope_discipline]] and [[feedback_verify_no_guessing]].
