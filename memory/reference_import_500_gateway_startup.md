---
name: reference_import_500_gateway_startup
description: "A 500 when selecting a REST API in the Entity/Connect import UI is usually HTTP 500.30 (Profisee gateway failed to start), not an import-code bug"
metadata: 
  node_type: memory
  type: reference
  originSessionId: 4220630b-2b26-4911-a43d-5ccc1e6a4bfd
---

When the Import Entity (`/metadata/entities`) or ConnEx/Connect import UI returns a **500 on selecting a REST API source**, check the Seq body before suspecting our code. If the body is **HTTP Error 500.30 — "ASP.NET Core app failed to start"**, that page is emitted by the *target's* hosting layer (IIS/ANCM) when the **Profisee gateway app itself crashed on startup** — it is path/verb-independent and impossible for an HTTP client (our import code) to cause.

Confirmed 2026-06-19: both `ModelMetadataHarvester` (GET `/profisee/rest/v1/Entities`) and `ConnExApiClient` (GET `/profisee/rest/v1/Connect/Configurations`) built the right URLs and got 500.30. Crucially, the **Profisee UI was up the whole time** — the deployment hosts multiple IIS apps and `/profisee/rest` is a SEPARATE app from `/profisee` (UI) and `/profisee/api/connex`. The REST app was crash-looping on startup because the `messaging` schema was missing the base queue table `[Services.Chatbot.Delayed]` (every other service had its base `Services.<name>.Delayed`; Chatbot had only the GUID-suffixed variant). A full clean platform rebuild reprovisioned the queues and fixed it.

**Don't trust MCP/UI "it works" as proof the gateway is up — they hit different apps.** Probe the REST app directly with curl.

**How to diagnose fast:**
- `curl -k -s -o /dev/null -w "%{http_code}" https://<host>/profisee/rest/`  vs  `…/profisee/health`. If `/profisee/rest/*` = **500** but `/profisee/health` = **302**, the REST sub-app is down (not our code). A healthy REST app returns **401** to an unauthenticated curl (needs `x-api-key`) — 401, not 500, means good.
- Seq: `@Message like '%ConnExApiClient%' or %ModelMetadataHarvester%` logs the exact target URL + failing body.
- Windows Application event log: look for crash-loop `.NET Runtime` Id 1000 (e.g. NServiceBus `Invalid object name 'messaging.Services.X.Delayed'`) and `IIS AspNetCore Module V2` startup-failure events. Verify a suspected missing queue via the SQL MCP against `sys.tables` in the `messaging` schema.
- Fix: reprovision the platform/messaging queues (clean rebuild or installer create-queues step), then recycle the `/profisee/rest` app pool. Nothing to change in TestAuto.Web.

Do **not** fabricate an import-code fix for this symptom. Related: [[reference_profisee_platform_log]] (gateway server-side errors in `Profisee.logging.tSystemLog`), [[seq-query]].
