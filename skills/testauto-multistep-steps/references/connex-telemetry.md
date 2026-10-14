# ConnEx Step — Telemetry and API Path Systems

Reference for the `testauto-multistep-steps` skill. Loaded on demand — see `SKILL.md` for the decision rules and gotchas that decide whether you need this file.

---

### ConnExStepDetail Telemetry

`ConnExStepDetail` is the structured telemetry object written per ConnEx step execution. It extends `UtilityStepDetail` with these ConnEx-specific fields:

| Field | Type | Description |
|---|---|---|
| `ResourceType` | string | `ServiceConfiguration`, `IntegrationStrategy`, or `ServiceProvider` |
| `Operation` | string | Operation executed; prefixed with `"DryRun:"` when `DryRun=true` |
| `EndpointPath` | string | Full endpoint path used (e.g., `v1/Connect/Configurations`) |
| `HttpStatusCode` | int? | Response status; null for DryRun |
| `ArtifactSizeBytes` | long? | Artifact file size before token replacement |
| `TokensResolved` | int | Count of `{{placeholders}}` successfully replaced |
| `UnresolvedTokens` | string[] | Token names that remained unresolved (empty on success) |
| `ApiErrors` | string[] | Parsed ConnEx API error messages on non-2xx responses |
| `ResponseSnippet` | string | Response body truncated to 2 KB |
| `ResponseTotalLength` | int | Full response body length before truncation |
| `ConnExResourceId` | string | Resolved resource GUID for Export/Delete |
| `OutputFilePath` | string | Resolved output file path for Export |
| `DriftDetected` | bool | True if Export found differences vs existing local file |
| `DriftSummary` | string | Human-readable diff of top-level key changes |
| `IsDryRun` | bool | True when step ran without issuing an HTTP call |

**How `ApiErrors` and `ResponseSnippet` are produced:**

- On a status code outside `ExpectedStatusCodes`, `ConnExErrorParser.TryParseErrors` (TestAuto.Utilities/Helpers) parses the response body into structured messages. It handles a root that is either a **single problem object or an ARRAY of them** (`EnumerateProblemObjects`, `ConnExErrorParser.cs:93`) — the gateway returns an array for multi-part failures, e.g. a delete reporting both a 404 "not found" and the underlying CDP 400.

Per object (`ExtractFromObject`, `:104`) it handles:

| Shape | Note |
|---|---|
| `errors` as an **array** | string items or `{message}` objects |
| `errors` as an **object** — `{ key: ["msg"] }` | **This is the shape that carries the real CDP codes**, e.g. `8602 : Cannot perform this operation because the member does not exist` |
| top-level `message` | — |
| `validationErrors` object | emitted `key: message` per entry |
| RFC 7807 `title`/`detail` | **only when that object produced nothing more specific**, so a generic "Request Failed" never displaces a real CDP code |

Messages are de-duplicated. The new `TryGetSemanticStatusCodes(body)` (`:64`) returns the nested `status` values so a caller can reconcile a misleading transport code against what the body actually reports. Parsed messages populate `ApiErrors` and the step `ErrorMessage`; when nothing parses (non-JSON body), the error falls back to the raw truncated snippet.
- `ResponseSnippet` (and the step `StandardOutput`) are head-truncated by the executor at `ConnExConstants.ResponseSnippetMaxLength` (2,048 chars) with a `... (truncated, total N chars)` marker; the untruncated body length is preserved in `ResponseTotalLength`.
- `ConnExExecutor` sets `StepExecutionResult.HttpStatusCode` directly from the HTTP response (`PowerShellRestExecutor` does the same for HTTP steps by parsing it from the PS wrapper output). HTTP-based steps are judged on HTTP status — distinguishable from the process `ExitCode`, which stays `null` for ConnEx steps.

### API Path Systems

ConnEx has **two distinct path systems**. The ConnExExecutor (used by `ConnExStep`) uses the REST gateway paths. The programmatic `ConnectRestClient` (used in C# scenarios) uses the versioned API paths.

| Resource | ConnExExecutor (Gateway) path | ConnectRestClient path |
|---|---|---|
| Service Configurations | `v1/Connect/Configurations` | `/v1/serviceconfigurations/import` |
| Integration Strategies | `v1/Connect/Strategies` | `/v1/integrationstrategies/import` |
| Service Providers | `v1/Connect/ServiceProviders` | `/v1/serviceproviders/import` |

This distinction matters when debugging 404 errors: a URL that works in ConnectRestClient will 404 if used in a ConnExStep `BaseUrl`, and vice versa.

---
