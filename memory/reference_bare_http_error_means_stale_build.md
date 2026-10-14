---
name: bare-http-error-means-stale-build
description: "A step error of the bare form \"HTTP 400: The remote server returned an error: (400) Bad Request.\" with no \" — <body>\" suffix means the deployed TestAuto build predates 2026-07-31 body capture"
metadata: 
  node_type: memory
  type: reference
  originSessionId: d4eacb8f-ad8c-4a79-8d46-5c4723d304dc
  modified: 2026-08-03T13:17:07.644Z
---

In `PowerShellRestExecutor.ExtractErrorMessage`, a captured response body is always appended as
`HTTP {code}: {msg} — {body}`. The **bare** form with no ` — ` suffix therefore proves no body was
captured, which on the `Invoke-RestMethod` path means the deployed build predates the fix commits.

Build cutoffs (speed-merchants):
- `2721be3f` / `43ea908a` (2026-07-31) — wrapper reads `$_.ErrorDetails.Message` FIRST and emits
  `HTTP_ERROR_BODY_B64:`. Before this, the wrapper only read `$ex.Response.GetResponseStream()`,
  which Windows PowerShell 5.1 has **already consumed** by the time the catch runs, so every 4xx
  body was silently lost.
- `74533b27` (2026-08-01) — adds `MatchesSemanticStatus`, which rescues a transport 400 whose body
  declares a status that IS in `ExpectedStatusCodes`.

Verify the deployed build without a version number by scanning the DLL for marker strings —
`HTTP_ERROR_BODY_B64`, `ErrorDetails`, `TryGetSemanticStatusCodes`. All absent = pre-fix build.
Deployed path pattern: `\\<box>\C$\Deploy\TestAuto.Web\TestAuto.Utilities.dll`.

Consequence for ConnEx: deleting a Connect service configuration that does not exist returns
transport **400** with a body declaring `status: 404` (+ CDP `8602 ... member does not exist`).
Generated delete steps whitelist `200,201,204,207,404` and NOT 400, so on a pre-fix build the step
hard-fails with no diagnosable message. See [[project_connex_delete_config_403_dependency]] and
[[reference_rest_connect_error_logging_audit]].

**Confirmed 2026-08-03**: workload `10000174` step 24 (Delete ConnectExport ServiceConfiguration)
failed with the bare form on the 2026-07-14 build. After redeploying current source, the full
Connect workload ran clean end-to-end — no step-24 change needed. Diagnosis was correct: stale
build, not a config or ordering defect. Reinforces the rule — check the deployed build's marker
strings BEFORE hunting a config cause for a bare HTTP error.
