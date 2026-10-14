---
name: json-case-insensitivity-audit
description: Codebase-wide audit (2026-06) of case-sensitive Newtonsoft key reads on external gateway/ConnEx/Connect/Matching JSON — the remaining offenders to convert to case-insensitive + constants
metadata: 
  node_type: memory
  type: reference
  originSessionId: 25f7dbe8-6d99-4da1-a08d-7ed23c825a54
---

Audit done 2026-06-28 (4 parallel agents, by subsystem) after the [[model-import-refdata-empty-body]] fix. Rule going forward: **never read external JSON keys case-sensitively; never use magic string key literals — use constants.** Root cause why casing varies = CDP contract resolvers (see [[model-import-refdata-empty-body]]).

**STATUS: ALL FIXED (2026-06-29).** Scaffolding added: `TestAuto.Shared/JsonHelpers/JTokenCaseInsensitiveExtensions.cs` (`GetValueCI`/`ValueCI<T>`/`SelectTokenCI`) + `TestAuto.Shared/Rest/GatewayJsonKeys.cs` constants (+ `SecretsEntityAttributes`, `MonitorKeys`, `ConnExConstants.ArtifactVersionField`). Every High/Med/Low site below converted to CI + constants. Build clean; unit suite 729 passed/0 failed; 5 new tests in `JTokenCaseInsensitiveExtensionsTests`. ONE deliberate exception: `ArtifactTokenScanner.cs:93` left as `SelectToken` (paths come from the artifact's own enumerated leaves so casing already matches, and `SelectTokenCI` doesn't support `[n]` array indexers that a hand-typed path could use). GOTCHA found: ConnEx import API expects the artifact version injected at root as PascalCase `ArtifactVersion` (request shape) — only READS are case-insensitive; that write key stays Pascal via `ConnExConstants.ArtifactVersionField`.

**HIGH (confirmed latent bug):**
- `TestAuto.Web/Services/ConnExApiClient.cs:158` and `TestAuto.Utilities/Executors/ConnExExecutor.cs:271` — `SelectToken("Configuration.artifactVersion")` capital "C" vs lowercase ConnEx export → always falls back to DefaultArtifactVersion. Fix: reuse the `SelectTokenCaseInsensitive` helper already in ArtifactTokenizer (promote to shared). ConnExExecutor.cs:269 already checks both casings — 271 was missed.
- `TestAuto.Web/Services/SecretSetupCommands.cs` (308/317,515-516,520-521,538,706,713,722) + `Components/Pages/SecretsBootstrap.razor.cs` (228,474,482) — capital `r["Code"]`/`r["Name"]` on records GET; system code/name proven camelCase → null (317 `r["Code"]!.ToString()` would NRE; 308 IsActive filter silently no-ops → old secrets never deactivated). Custom attrs (IsActive/SecretData/MachineName) are dict keys → keep model casing → likely OK but still rule-violating.

**MEDIUM (works only because casing currently matches; fragile):**
- REST layer: `TestAuto.Shared/Rest/JsonResponse.cs:15,62` (errors/data envelope), `Rest/CreatedRecordsResponseExtensions.cs:70`, `TestAuto.Shared.Http/Facades/EntityDataFacade.cs:136`, `Rest/RestClient.cs:556` (data envelope), `JsonHelpers/AttributeJsonConverter.cs:17,18,23,28`, `JsonHelpers/EntityJsonConverter.cs:27`, `Rest/OAuthTokenProvider.cs:86,88`.
- Connect: `ConnectStrategyPollingScenario.cs:206,243`, `ConnectPostRunCollectionScenario.cs:293` (data/Code/ProcessingState miss → null → NonTerminal → silent 12h poll timeout), `ConnectExecutionRepository.cs:196,206` (monitor Properties JSON).
- Matching: `MatchingOperationExecutor.cs:119,179` (totalRecords → silent 0 → spurious creates), `466,469,471` (data/record golden-record extraction).
- Web: `WebUiRepository.cs:1102`, `WorkflowExecutionService.cs:1164`, `WorkflowScenariosEditor.razor.cs:696` (data/errors — low).

**LOW / already-mitigated:** `MonitorActivityCollector.cs` (dual-casing fallback), `ConnExErrorParser.cs:85,86`, `ConnExArtifactMasker.cs:63,69` (redaction gap not null-return), `ArtifactTokenScanner.cs:93` (round-trips own casing).

**Clean:** MetadataImport (post-fix; constants lowercase + OrdinalIgnoreCase), TemplateController (own PascalCase schema), SeqEventParser (Seq not gateway), PrometheusClient/PaginatedRecords (JsonProperty attrs), ConnectRestClient (request bodies), RecordMix/CustomParms (config), SQL readers.

**Systemic fix:** shared `GetValueCI`/`SelectTokenCI` extensions + key constants; consider an analyzer/grep guard banning `jobj["..."]`/`SelectToken` on gateway JSON.

**Convention now lives in skill `external-json-case-insensitive-reads`** (created 2026-06-30 skill audit) — go there for the API, the keys-as-constants rule, and before/after examples. This audit memory is the historical offender list; the skill is the forward-looking how-to.
