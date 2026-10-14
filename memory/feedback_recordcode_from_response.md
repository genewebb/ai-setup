---
name: Record codes must come from API response
description: When creating records via Profisee API, always get record codes from the create response (CreatedRecordCodes), not the input record. All records must have a record code.
type: feedback
originSessionId: 6dd4a754-4cbb-467c-803e-cc19ab4738f2
---

Record codes should always be sourced from the Profisee create API response (`CreatedRecordCodes`), not from the input record. All records must have a record code — this is a hard requirement, not optional.

**Why:** Auto-coded entities don't have a Code on the input record; Profisee generates it server-side. Reading from the input was the root cause of zero records in the tracking entity.

**How to apply:** Any code that creates records and needs the resulting code should read `createDetail.CreatedRecordCodes` as the primary (and expected) source.
