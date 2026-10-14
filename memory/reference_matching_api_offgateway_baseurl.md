---
name: reference-matching-api-offgateway-baseurl
description: "Matching/auth API routes are NOT behind the REST gateway — they need the /rest/-stripped base, not the {{...:BaseUrl}} token"
metadata: 
  node_type: memory
  type: reference
  originSessionId: f86f801d-8fa1-4f8c-ba7e-0e5a5125487b
---

Profisee **matching API** routes (`/api/matching/...`, e.g. `/api/matching/health`, `/api/matching/v1/strategies/{name}/IdleStatus`) and the **auth** endpoint (`/auth/connect/token`) live **off the REST gateway** — under `https://<server>/profisee/`, NOT under `…/profisee/rest/`. The configured `RestClients:*:BaseUrl` ends in `/rest/`, so:

- C# derives the right base by **stripping `/rest/`** — see `MatchingStrategyPollingScenario.StripRestSuffix` / `MatchingApiStatusPoller` (TestAuto.Matching). Result: `https://<server>/profisee` (no trailing slash), then append `/api/matching/...`.
- The **MultiStep token templater (`TextTemplater`) cannot strip** — it does literal substitution only (no transforms). So a MultiStep Http step CANNOT build `/api/matching/...` from the `/rest/` `{{$config:...:BaseUrl}}` token. Appending to it yields the doubled `…/profisee/rest/api/matching/health` → **405 Method Not Allowed** (the correct URL `…/profisee/api/matching/health` returns 200).

**Fix/convention:** add a sibling `ApiBaseUrl` to the `RestClients:Matching` secret section (which is `includeInReplacements: true`), built from `{{ServerNames:ApplicationServerName}}` so the host stays single-sourced (no drift):
`"ApiBaseUrl": "https://{{ServerNames:ApplicationServerName}}.corp.profisee.com/profisee"`
then step `url`: `{{$config:RestClients:Matching:ApiBaseUrl}}/api/matching/health`.

Gotcha: `ExternalLinks:Application:BaseUrl` is already exactly `…/profisee` but its section is `includeInReplacements: false` (admin links, not for token replacement) — so it does NOT resolve as a `{{$config:...}}` token; don't flip it.

Secret file structure (per-section): `category`, `description`, `includeInReplacements`, `values{}`; internal refs use bare `{{Section:Item}}` (e.g. `{{ServerNames:ApplicationServerName}}`, `{{RestKeys:ProfiseeRestKey}}`) which the secrets layer resolves before publishing to IConfiguration, where runtime `{{$config:Section:Item}}` then reads them. See [[reference-profisee-health-endpoint-503]], [[reference-scenario-config-token-prefix]], [[testauto-multistep-steps]].
