---
name: reference_read_path_that_writes_fails_under_load
description: "A durable-store read or refusal that rewrites its record turns a momentary Windows file handle into a false outage — and, on a release path, into state that stays locked forever."
metadata: 
  node_type: memory
  type: reference
  originSessionId: 05a61cd5-462a-479d-b5d9-1ae50f21dcb5
  modified: 2026-09-20T15:19:11.454Z
---

A compare-and-swap store built as `WithLock(record => (record, result))` writes the record back on
**every** path, including pure reads and refusals. On Windows a scanner or the search indexer holds a
handle for a few milliseconds under load, so:

- a **read** returns `STATE_UNAVAILABLE` although the store was perfectly readable;
- a **release** is refused, and the installation's single root-run slot stays held by a run that has
  already finished — no further run can be admitted without manual intervention.

**How it presents:** a test that passes in isolation and fails inside a loaded full suite. That is the
signature, not noise. Found in speedmerchants 2026-09-20 (Goal 5, `FileRootRunSlot`).

**How to apply:** let the decision function return `null` for the record to mean *decided, wrote
nothing*, and take that path for every read and every refusal — a refusal that rewrites the file can
fail, and is then reported as an outage rather than as the refusal it was. Separately, wrap the whole
locked operation in a bounded retry on `IOException`: a transient handle leaves the stored state
untouched, so re-running is safe, while an unreadable store must still eventually be reported.

Related: [[feedback_verify_no_guessing]], [[reference_factory_lambda_hides_missing_di_dependency]]
