---
name: reference-profisee-gateway-401-echoes-api-key
description: Profisee REST gateway 401 body (error 2070 invalid_client) quotes the full X-Api-Key back; never print a 401 body
metadata:
  node_type: memory
  type: reference
  originSessionId: e6692ca4-4cf5-4b6c-9bc6-113c26f431a3
  modified: 2026-10-13T15:27:00.510Z
---

Profisee 26.3 REST gateway, rejected key: HTTP 401, body
`{"errors":{"2070":["REST Gateway received an error from the auth service when supplying API Key <FULL KEY>. Auth Error: invalid_client"]}, ...}`.

**Why:** on 2026-10-13 I printed that body while diagnosing CORPVM17's SUT and leaked the SM_SUT_APIKEY value into the
transcript. speedmerchants' ProbeTarget/Hide-Secret exist for exactly this reason.

**How to apply:** when probing a Profisee REST endpoint with a key, print only the status code and the error code
(e.g. 2070 / invalid_client), never `$response.Content`, or mask the key in it before printing. invalid_client = the
key matches no user's client ID on that instance (or the auth service cannot validate it).
