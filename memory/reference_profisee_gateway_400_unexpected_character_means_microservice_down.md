---
name: reference_profisee_gateway_400_unexpected_character_means_microservice_down
description: "Profisee gateway answers HTTP 400 {\"status code\":[\"InternalServerError\"],\"message\":[\"Unexpected character encountered while parsing value: <\"]} when a proxied microservice is DOWN - it is JSON-parsing an IIS 500.30 HTML page; diagnose at /profisee/api/<svc>/health, not in the request"
metadata: 
  node_type: memory
  type: reference
  originSessionId: 6f0d3904-49de-4741-a701-439ff517a35a
  modified: 2026-09-12T02:45:29.368Z
---

**Signature** (seen 2026-09-11, SMVM2, every Matching route including `GET /v1/Matching` which names no strategy):

```
HTTP 400  {"status code":["InternalServerError"],"message":["Unexpected character encountered while parsing value: <. Path '', line 0, position 0."]}
```

**Meaning**: the gateway proxied to a microservice, got back an **HTML** page (IIS `500.30 - ASP.NET Core app failed to start`), and choked JSON-parsing the `<`. It is NOT a request-validation error even though it is a 400. A *disabled strategy* or bad payload cannot produce it — a data row cannot stop an ASP.NET Core app from starting.

**Discriminators**
- `GET https://<host>/profisee/api/matching/health` → HTML `500.30` = service down; JSON `{"status":"Healthy"}` = up (BulkScoring at `/api/bulkscoring/health` is a good sibling control).
- A route that names no strategy (`GET /v1/Matching`) failing identically rules out strategy config.
- Profisee's swagger documents the lookup's strategy failure as **404 "Invalid Strategy Name"**, and real request-validation as **400 error code `2219`** with a readable message — see [[reference_lubc_2219_is_request_validation]].
- The service's own `…\Services\Matching\LogFiles\SystemLog_NNN.log` stops being written; Application log may show NOTHING new because `stdoutLogEnabled="false"` in its `web.config` — the last recorded startup exception can be days stale.

**Why TestAuto showed it as a blank error**: `JsonResponse.GetErrors()` only reads an `errors` key; this body has none, so `HttpErrorMessage` was `""` on 100,000 rows. Fixed by `RestErrorText.Describe` (falls back to `RawErrorBody`), committed in `60b30c0b`.

Related: [[project_smvm2_matching_service_down_2026-09-10]], [[reference_documented_security_property_never_tested]] (same lesson: test the live thing, not the record of it).
