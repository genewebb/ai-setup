---
name: crewchief-connect-import-apikey-globals
description: "2026-08-19 ConnEx 401 root cause (literal {{RestKeys:...}} stored as secret) + new ConnExBaseUrl/ConnExApiKey workload globals and V14 guards"
metadata: 
  node_type: memory
  type: project
  originSessionId: 0d3e6080-6cbb-498b-84b2-6ad6084ac90d
  modified: 2026-08-19T22:08:34.268Z
---

**Field failure 2026-08-19:** connect-import workload got `401 invalid_client` — gateway received literal `{{RestKeys:ProfiseeRestKey}}` as x-api-key. Chain: user's CrewChief secrets store (`C:\ProgramData\CrewChief\secrets`) was imported from a file whose `RestClients:Connect:ApiKey` = `{{RestKeys:ProfiseeRestKey}}` but WITHOUT the `RestKeys` section; `SecretSchema.ValidateInternalReferences` only errored when the section existed but the key didn't, so the dangling ref stored verbatim; `ConnExExecutor.ResolveValue` never templates the config fallback, so the literal shipped. Remedy on the box: /secrets → Replace with the FULL `C:\devopslocal\Secrets\corpltr94.crewchief.json` (has RestKeys; import resolves internal refs), or paste the real key into the workload global.

**Shipped fixes (all in repo, 3013 unit tests green):**
1. `ConnExStepSetBuilder` now promotes `ConnExBaseUrl`/`ConnExApiKey` workload globals (defaults `{{$config:RestClients:Connect:BaseUrl/ApiKey}}`, names/defaults in `ConnExConstants`); every emitted step's `baseUrl`/`apiKey` references them — operator maps to a secret or pastes a literal per environment (user decision).
2. `ConnExExecutor` V14a/V14b: unresolved `{{token}}` remaining in BaseUrl/ApiKey fails the step locally, never calls the gateway; `SecretScrubber.Register` moved AFTER the check so the token name isn't masked in the error.
3. `SecretSchema.ValidateInternalReferences`: a `{{Section:Key}}`-shaped ref to a section absent from the file now REJECTS the import (bare `{{Placeholder}}` without colon still allowed).

**SUPERSEDED same day — user ruled ConnEx steps MUST get capability coverage.** Shipped `StepCapability.ConnExParameters` (8th capability, one-per-prober rule kept): every ConnExStep derives one requirement; `ConnExParametersProber` + `CapabilitySubsystemRegistration.BuildConnExParameterReport` verify every consumed `{{token}}` (inline artifact, resourceId, effective BaseUrl/ApiKey incl. `RestClients:Connect:*` fallbacks, multi-pass two-hop resolution) is present AND non-empty. Missing/empty both Failed/Deterministic → hard-block, names each parameter. Local/live (not network, in `ResolvesFromStepScope` so per-step dedup). User ruling: presence-only is enough — "as long as an apikey is configured if it gets a 401 that is fine" (no gateway acceptance probe). Enhancement backlog: `speed-merchants\planning\Backlog_CapabilityChecker_Enhancements.md` (checker is critical for non-dev users). ConnEx RunAsUser remains an artifact parameter, not a process Run-As. Storage layout confirmed: workloads/steps/runs/reference-kv under install dir `web\data` (`CrewChief:DataFolder`, default `data` under content root); only secrets + dataprotection-keys live in ProgramData (machine-shared by design for service accounts).

Related: [[crewchief-connect-import]] [[crewchief-secrets]] [[crewchief-capability-preflight]] [[project_crewchief_connex_import_three_bugs]] [[unit-tests-no-outside-artifacts]]
