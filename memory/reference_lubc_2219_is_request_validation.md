---
name: reference_lubc_2219_is_request_validation
description: "Profisee LUBC error 2219 (\"did not meet the minimum field requirements for match evaluation\") validates the SUBMITTED payload against the strategy's attribute sets before touching any record - strategy-side record filters cannot prevent it; only what TestAuto sends can"
metadata: 
  node_type: memory
  type: reference
  originSessionId: 6f0d3904-49de-4741-a701-439ff517a35a
  modified: 2026-09-12T02:45:41.672Z
---

`POST /v1/Matching/{strategy}/lookup` → **HTTP 400, code `2219`**, message lists every attribute-set combination, e.g. `IDNumber, DateOfBirth | IDNumber, FirstName, LastName | DateOfBirth, AddressLine1, LastName, PostalCode, FirstName | Phone Number, FirstName, LastName, IDNumber | HomeEmail, FirstName, LastName, IDNumber`.

**Proven live 2026-09-11 (CORPLTR94)**: `{FirstName, LastName}` alone → 2219 with the model full of matches; `{IDNumber, DateOfBirth}` → 200, 5 matches. So it is request-side. Excluding a source system in the *strategy* (set criteria / clear criteria) narrows candidates, not the inbound check — it does not help.

**What produced it in TestAuto**: `BuildLookupPayload` (`MatchingOperationExecutor.cs:436`) omits blank fields (`value?.ToString()?.Trim()` null/empty). ModelSource source system **Credibly** carries ~15% independent blanks on every lookup field except HomeEmail (the shape's protected uniqueness column) via `MutationOverrides.BlankRate` — a **per-source-system** dial (`MutationShape.cs:349`), not a shipped default (no `PersonFieldPack` kind suggests `Blank`). Text blanks are `''`, `DateOfBirth` is `NULL`. Five of six RetailClient attribute sets require `IDNumber`, so 15%/field ⇒ ~11.9% of Credibly rejected; Walmart 1.58%, Intuit 0.6%, Apple/Seed 0.

**SQL "blank" must match the payload builder**: `NULLIF(LTRIM(RTRIM([col])),'') IS NOT NULL` — a plain `IS NOT NULL` passes the empty strings straight to a 2219. `date` columns use `IS NOT NULL`.

**3b is worse than 3a**: `ExecuteLookupThenCreateAsync` (`:169-178`) returns on a failed lookup and **never creates the record** — silently drops it from the create+match sample.

Fix landed 2026-09-12: [[project_matching_3a_target_pull_and_quality_dial]].
