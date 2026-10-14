---
name: project_crewchief_http_curl_split
description: CrewChief HTTP step split into two distinct steps — HttpRequestStep (structured REST) and CurlStep (raw curl command)
metadata: 
  node_type: memory
  type: project
  originSessionId: 08e95719-a0d7-4939-83f7-2163348e1d0b
---

The single fused HTTP step (a `useRestMethod` bool toggling curl vs Invoke-WebRequest) was split into TWO first-class steps (2026-07-17):
- **HttpRequestStep** — Type `"HTTP"`, structured method/url/headers/body, executed by `PowerShellRestExecutor` (`Invoke-WebRequest`). `useRestMethod`/`customCurlArgs` removed.
- **CurlStep** — Type `"CURL"`, a raw `command` curl-syntax string (paste "Copy as cURL"), executed by `CurlExecutor` → `curl.exe`.

Both `StepType` keys register separately; wiring updated in `StepTypeRegistry`, BOTH `CreateStepForType` factories (Steps.razor.cs + WorkloadEditor.razor.cs), `UtilityStepTypeInfo.AllTypes`, the orchestrator aliases, and DI. The "curl drain race" `WaitForExit()` fix is preserved in both executors.

**Important:** TestAuto never actually modeled these as two steps (it also used the `useRestMethod` toggle) — this was a CrewChief *improvement*, not a parity fix. Help docs: `/help/step-guides/http` (REST) + `/help/step-guides/curl`. See [[project_crewchief_steptype_factory_duplicated]].
