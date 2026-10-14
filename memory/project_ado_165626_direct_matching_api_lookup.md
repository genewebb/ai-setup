---
name: project_ado_165626_direct_matching_api_lookup
description: ADO 165626 — 3C lookups direct to Matching API via new MatchingApiRest secrets target; prelim doc in vault 99 Documentation/matching/UpdateToMatchingScenario
metadata:
  node_type: memory
  type: project
  originSessionId: c5f4589d-90cc-4cbc-afdf-de32cebaefdd
  modified: 2026-10-12T14:49:50.756Z
---

ADO 165626: make UnifiedMatchingScenario (3C, LookupThenCreate) send LOOKUPS straight to the Matching API, bypassing the REST gateway. Gene decided (2026-09-24): adapt the harness, not the gateway; add a `MatchingApiRest` REST target to secrets (`RestClients:MatchingApiRest`).

Preliminary requirements/implementation doc: `Q:\Work\Work\99 Documentation\matching\UpdateToMatchingScenario\DirectMatchingApiLookup.md`.

Verified facts (code, 9/24):
- Direct URL `{host}/Profisee/api/matching/v1/strategies/{name}/actions/lookup/invoke`; body `{record, additionalAttributes}`; response `records[]`; statuses 200/400/403/404/409/422; no 429/Retry-After until 165628.
- Token: `{host}/Profisee/auth/connect/token`, client_credentials, client_id = api key, scope ProfiseeAPI — `OAuthTokenProvider` + `MatchingApiStatusPoller` already do this.
- Gateway maps all but 404/401 to 400, drops processAllAttributeSets, and re-parses numbers/dates (`Helper.ToLookUpValues`).
- `RestSubjectArea.Matching` carries lookup AND create AND reads, so it cannot just be repointed; `RestClientFactory` never applies the resolved BaseUrl; `RestUrlManagement` silently falls back to Profisee gateway.

Gene decisions 9/24: open-loop driver = Phase 2 only if needed; outcome/status/Retry-After = new columns on UnifiedMatchingApiExecution; send lookup values as-is (probe first); name = MatchingApiRest.

10/12: 165628 and 165629 shipped as ONE per-process registration gate on matching main (PR 26288, build 208270). It gates only new-value WRITES. Limits: 2 permits, 300 waiting, 60 s wait; past either, 429 + Retry-After 60. The gateway turns that 429 into a 400. Impact and plan doc (proposed, unbuilt): `LubcAdmissionControlImpact.md` in the same folder. It amends this doc: refusal code 429, timeout 300 s, new TimedOut outcome.

**Why:** The gateway hides busy refusals (165628) and adds its own latency to the throughput baseline.
**How to apply:** Build from the doc; default `LookupTarget=Gateway` keeps other runs unchanged. Open Qs are in doc §6.
