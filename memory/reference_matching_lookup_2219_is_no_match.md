---
name: reference-matching-lookup-2219-is-no-match
description: "Matching API lookup HTTP 400 status code 2219 (minimum field requirements) = no existing record returned, NOT an error; LookupThenCreate must still create"
metadata:
  node_type: memory
  type: reference
  originSessionId: b1262713-be4a-4236-98d5-5b07cd38bb7c
  modified: 2026-10-08T13:38:38.851Z
---

Matching lookup returning HTTP 400 `{"status code":["2219"],"message":["...minimum field requirements for match evaluation..."]}` means the record lacks every field combination the strategy matches on. Gene: it is NOT an error and NOT "not evaluated" — the lookup's purpose is to return an existing record; 2219 = none returned, so LookupThenCreate creates the record (it then matches, even as a unique). LookupOnly: no-match row.

Handled 2026-10-08 in speed-merchants `TestAuto.Matching/Helpers/InsufficientMatchFieldsResponse.cs` + `MatchingOperationExecutor` (log Information, row Complete).

**How to apply:** never count 2219 as a failed batch; never word it as "skipped"/"not evaluated" in logs/docs.
