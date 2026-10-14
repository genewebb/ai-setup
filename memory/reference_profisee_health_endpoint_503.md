---
name: reference-profisee-health-endpoint-503
description: Profisee /rest/health aggregate returns HTTP 503 when ANY single service check is Unhealthy; browsers mask the status code
metadata: 
  node_type: memory
  type: reference
  originSessionId: f86f801d-8fa1-4f8c-ba7e-0e5a5125487b
---

The Profisee gateway `{{BaseUrl}}health` (e.g. `https://<server>/profisee/rest/health`) is an ASP.NET HealthChecks aggregate. It returns **HTTP 503 if *any one* of its ~18 individual checks is `Unhealthy`**, even when everything else (BulkScoring, Matching, Data, Auth, etc.) is `Healthy`. The body is JSON: `{"status":"Unhealthy", "healthChecks":{ "<Service>":{"status":"Unhealthy","description":"..."} }}`. `Unhealthy → 503`, `Healthy → 200`.

**Debugging traps that cost time on this:**
- **A browser makes it look fine** — it renders the 503 JSON body without surfacing the status code, so "works in browser" is a false positive. PowerShell `Invoke-RestMethod` *throws* on the 503 (use `-SkipHttpErrorCheck` in PS7 to read the body). Always check the actual HTTP status, not just that a body came back.
- **A near-instant (0ms) 503 is still a real gateway response** here — health aggregation is fast (~0.4s), so don't assume 0ms means a proxy/local short-circuit.
- Health endpoint is **anonymous** (no api-key needed); the key/subject-area is irrelevant to whether it 503s.

**Design caveat for pre-flight "ping before run" steps:** gating a run on the aggregate `/health` couples it to *every* service. A `Ping BulkScoring Before Run` step against `/health` will block when an unrelated service (e.g. Workflow) is down even though BulkScoring is Healthy. To gate on one service, use a PowerShell step that GETs `/health` and asserts `healthChecks.<Service>.status -eq 'Healthy'` — the MultiStep HTTP step only checks status codes, not body content. See [[testauto-multistep-steps]].

Observed real case (2026-06): SMVM2 `/health` = 503 because only `Workflow` was Unhealthy ("Discover endpoint #0 ... InternalServerError"); all other services incl. BulkScoring Healthy. TestAuto runner that calls it is `SMVMTR2` as `CORP\QAAutomation`.
