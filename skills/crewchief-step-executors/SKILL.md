---
name: crewchief-step-executors
description: >
  Catalog of CrewChief's distinctive step executors (SQL, ConnEx, HTTP/curl, CLU, SetApiKey, DB-ops,
  CheckPort, Teams, WebSite) and their non-obvious behaviors. Use when authoring or debugging any of
  those steps, adding a step type, tracing a step routed to the wrong executor, or reasoning about SQL
  GO-batch pass/fail wrapping, ConnEx artifact tokenization, curl status parsing, API-key encryption,
  Configuration.exe exiting 0 on failure, DB-ops authMode, SQL Run As / double-hop,
  restore-under-a-different-name (relocateFiles), waitIndefinitely, a port-reachability probe, a Teams
  webhook notification, IIS site/application deletion and orphaned pools, or the built-in protections
  that refuse an operation with no override flag.
---

Repo: speed-merchants (paths below are repo-relative)

# CrewChief Step Executors

CrewChief is a standalone .NET 10, files-only step/workflow automation tool inside the speed-merchants repo (`CrewChief\`). It is a READ-ONLY copy derived from the internal "MultiStepUtility" scenario with ZERO TestAuto references; it uses Newtonsoft.Json and Serilog. This skill documents the *distinctive* step executors in `CrewChief.Engine`. For the general executor contract (`IStepExecutor`, orchestration, DI) see [[crewchief-executor-pattern]]; for the remote box-prep executors (Install/Uninstall/Configure/IisReset/ServiceControl/AppPool + the remote transport) see [[crewchief-remote-box-prep]].

## When to Use
- "Why did my SQL step report success even though a later GO batch threw?"
- "How do I point a CrewChief SqlStep at a different server per step?"
- "My ConnEx import 400s / the artifactVersion keeps getting overwritten."
- "Do I use the HTTP step or the curl step for this request, and why is my status code not validated?"
- "How does the SetApiKey step store the encrypted key without leaking it?"
- "I added a new step type but it runs as a CommandLineStep — where's the registry?"
- "Configuration.exe exited 0 and the step went green, but nothing was actually configured."
- "How does a DB-ops step authenticate to a remote SQL server — SQL login or run-as a Windows account?"

## Step Type Registry (single source of truth)

`StepTypeRegistry` (`Steps/StepTypeRegistry.cs`) maps every step `Type` string (canonical + aliases, case-insensitive) to a CLR type and a factory. Both `UtilityStepConverter` and `UtilityStepBase.CreateFromJToken` consult it, so a new step type is added in ONE table. Executors are registered separately in `EngineServiceCollectionExtensions.AddCrewChiefEngine` as `IStepExecutor`; each executor's `StepType` property + `CanExecute(step)` (a runtime `is` type-check, so aliases still match) select it.

| Canonical `Type` | Aliases | Step class | Executor | Notes |
|---|---|---|---|---|
| `sqlstep` | `sql` | `SqlStep` | `SqlScriptExecutor` | Dual source/dest conns, GO split, pass/fail wrap |
| `powershellstep` | `powershell`, `ps` | `PowerShellStep` | `PowerShellScriptExecutor` | Inline `scriptContent` |
| `commandlinestep` | `commandline`, `cli`, `cmd` | `CommandLineStep` | `CommandLineExecutor` | What the **Web editors'** `CreateStepForType` falls back to for an unregistered type (deserialization throws instead — see below) |
| `clustep` | `clu` | `CLUStep` | `CLUExecutor` | Profisee CLU.exe; exit code 1=success |
| `httprequeststep` | `httprequest`, `http` | `HttpRequestStep` | `PowerShellRestExecutor` | StepType `"HTTP"` (structured REST) |
| `curlstep` | `curl` | `CurlStep` | `CurlExecutor` | StepType `"CURL"` (raw curl) |
| `connexstep` | `connex` | `ConnExStep` | `ConnExExecutor` | **7** ops (`WaitForBatch` added); gateway HttpClient |
| `waitstep` | `wait` | `WaitStep` | `WaitExecutor` | |
| `mapsharestep` | `mapshare` | `MapShareStep` | `MapShareExecutor` | Owns `IsLocalTarget` shared rule (FQDN-aware, see below) |
| `servicecontrolstep` | `servicecontrol`, `service` | `ServiceControlStep` | `ServiceControlExecutor` | Box-prep → [[crewchief-remote-box-prep]] |
| `healthgatestep` | `healthgate`, `health` | `HealthGateStep` | `HealthGateExecutor` | |
| `databaseoperationsstep` | `databaseoperations` | `DatabaseOperationsStep` | `DatabaseOperationsExecutor` | `authMode` Windows/Sql + impersonation (below) |
| `apppoolstep` | `apppool` | `AppPoolStep` | `AppPoolExecutor` | Box-prep → [[crewchief-remote-box-prep]] |
| `uninstallstep` | `uninstall` | `UninstallStep` | `UninstallExecutor` | Box-prep → [[crewchief-remote-box-prep]] |
| `installstep` | `install` | `InstallStep` | `InstallExecutor` | Box-prep → [[crewchief-remote-box-prep]] |
| `configurestep` | `configure` | `ConfigureStep` | `ConfigureExecutor` | Box-prep → [[crewchief-remote-box-prep]] |
| `setapikeystep` | `setapikey` | `SetApiKeyStep` | `SetApiKeyExecutor` | RSA-encrypt → `meta.tUser` |
| `iisresetstep` | `iisreset` | `IisResetStep` | `IisResetExecutor` | Box-prep → [[crewchief-remote-box-prep]] |
| `emailstep` | `email` | `EmailStep` | `EmailExecutor` | BCL `System.Net.Mail` behind `IEmailSender` |
| `teamsstep` | `teams` | `TeamsStep` | `TeamsExecutor` | Adaptive Card via a Power Automate Workflows webhook, behind `ITeamsSender`; LogTag `TEAMS` |
| `checkportstep` | `checkport` | `CheckPortStep` | `CheckPortExecutor` | Non-mutating LOCAL-only TCP assertion behind `ILocalTcpPortProbe` |
| `websitestep` | `website`, `site` | `WebSiteStep` | `WebSiteExecutor` | Box-prep (7th) → [[crewchief-remote-box-prep]]; IIS site start/stop/delete + web-app delete |

### Unknown `Type` — TWO different behaviors, do not conflate them

`StepTypeRegistry` itself has **no default/catch-all registration**: `TryResolve` (`StepTypeRegistry.cs:109`) is a plain case-insensitive `Dictionary.TryGetValue` returning `false`, and `CreateStep` (`StepTypeRegistry.cs:126`) returns **`null`** for an unknown type — its own doc-comment says "never a silent fallback to some default step". What happens next depends entirely on which caller asked:

| Path | Caller | Unknown type does |
|---|---|---|
| **Deserialization — THROWS** | `UtilityStepConverter.ReadJson` | `throw new JsonSerializationException($"Unknown step type: {stepType}")` (`UtilityStepConverter.cs:49`; a missing `Type`/`type` property throws at `:41`) |
| **Deserialization — THROWS** | `UtilityStepBase.CreateFromJToken` | `throw new NotSupportedException($"Step type '{stepType}' is not supported. Supported types are: …")` (`UtilityStepBase.cs:109`; missing `type` → `InvalidOperationException` at `:100`) |
| **Web "Add Step" UI factory — SILENTLY FALLS BACK** ⚠️ | `Steps.CreateStepForType` (`Steps.razor.cs:640`) and `WorkloadEditor.CreateStepForType` (`WorkloadEditor.razor.cs:554`) | `StepTypeRegistry.CreateStep(type) ?? new CommandLineStep()` — an unregistered type becomes a **`CommandLineStep`** with no error |

So a saved/imported step file carrying a bogus `type` **fails loudly** at load, but a *new* step type wired into a UI picker without a matching registry entry **silently materializes as a command-line step** in the editor — that is the live footgun behind "I added a new step type but it runs as a CommandLineStep". Both editor sites carry the identical `?? new CommandLineStep()` tail and must stay in sync (see memory [[project_crewchief_steptype_factory_duplicated]]). Add every new type to `StepTypeRegistry` (and its executor to DI).

---

## SQL — `SqlScriptExecutor`

`Executors/SqlScriptExecutor.cs` + step `Steps/SqlStep.cs` + helper `Helpers/GoBatchSplitter.cs`.

**Deliberate `Microsoft.Data.SqlClient` exception.** This executor uses ADO.NET `SqlConnection`/`SqlCommand` directly instead of any `SqlHelper` (documented in its class remarks). Reasons: (1) it wires `SqlConnection.InfoMessage` to Serilog so `PRINT` / `RAISERROR ... WITH NOWAIT` stream live from long scripts; (2) it needs a per-command timeout override (`SqlCommandTimeoutSeconds`, `0` = infinite — for multi-hour loads); (3) multi-batch transaction management needs one connection held across N batches. This is the sanctioned deviation from the SqlHelper rule (cf. [[dotnet-sql-data-access]]).

**Dual source/destination connections.** `SqlSourceConnectionSecretName` (read) and `SqlDestinationConnectionSecretName` (write) are BOTH required (`CanExecute`). Both open upfront with `InfoMessage` wired. Routing (`ExecuteSingleBatchAsync`): **batch 0 routes to SOURCE only when scalar capture is effective**; all other batches route to DESTINATION (inside the transaction).

**Connection resolution** (`ResolveConnectionString`): a value containing `{{` is treated as a secret reference and token-resolved directly to the connection string (lets each step target any server from the secrets file, e.g. `{{$config:ConnectionStrings:ProfiseeDB}}`); a bare name falls through to `GetConnectionString` → `ConnectionStrings:<name>` → the legacy `ProfiseeAppSettings` aliases (`ProfiseeDB`/`MessagingDB`/`MonitorDB` via `SqlConnectionStringSecretAliases`). Timeout is baked into the connection string via `SqlConnectionStringBuilder.CommandTimeout`.

**GO batch splitting** (`GoBatchSplitter.SplitBatches`): comment/string-aware character-by-character split (skips `GO` inside `--`, `/* */`, and single-quoted strings), regex `^\s*GO\s*(\d+)?\s*$` on its own line, and honors `GO n` repeat counts (returns `List<(BatchText, RepeatCount)>`). (`SplitBatchesSimple` and `ValidateScript` also exist but the executor uses `SplitBatches`.)

**Pass/fail wrapping** (`AutoWrapPassFailCode`, default **true**). `WrapSqlWithPassFailCode` wraps EACH GO batch in `BEGIN TRY … END TRY BEGIN CATCH … END CATCH` that always ends with `SELECT @PassFailCode, @PassFailErrorMessage` (0 = pass, 1 = fail). The CATCH also `RAISERROR(...,10,1) WITH NOWAIT` (severity 10 = informational, does NOT abort) so the real error streams via `InfoMessage`. Enabling this implicitly forces scalar capture (`effectiveCaptureScalar = CaptureScalarResult || AutoWrapPassFailCode`).

> **Footgun / fixed bug (NEW-3):** the CATCH severity-10 RAISERROR never aborts, so a failing wrapped batch produced no exception. Wrapped batches `>= 1` (destination) previously ran via `ExecuteNonQuery`, discarding the final pass/fail SELECT → a later-batch failure was silently swallowed and the step reported success. Fix: `readScalar = useSource || AutoWrapPassFailCode` — wrapped batches re-read the scalar, and a non-zero code is **re-thrown** as `InvalidOperationException` so the transaction rolls back and the step fails.

**Transaction-incompatible DDL.** `IsTransactionIncompatibleError` matches messages like `CREATE/ALTER/DROP DATABASE statement not allowed within multi-statement transaction`. When `SqlAllowNonTransactionalBatches` is set and such a `SqlException` fires inside a transaction, the executor **commits prior batches, retries the batch non-transactionally**, then re-opens a transaction for remaining batches.

Other flags: `UseTransaction` (default true, single dest transaction, rollback on any throw), `CaptureScalarResult`, `DryRun` (resolves + reports the SQL that WOULD run, opens no connection). `InputText`/dry-run output truncate to 4000 chars for metrics. Inline `SqlScript` is the only content source (file/scriptKey retired).

---

## ConnEx — `ConnExExecutor`

`Executors/ConnExExecutor.cs` + `Steps/ConnExStep.cs` + `Steps/ConnExConstants.cs`. Calls the Profisee Connect gateway over a **named `IHttpClientFactory` client** — NOT a `ConnectRestClient`.

**Six operations** (`Operation`, default `Import`): `Import`, `Export`, `Delete`, `Enable`, `Disable`, `Execute`. HTTP method + path per op (built from `ConnExConstants.GatewayPaths`, i.e. `v1/Connect/Configurations|Strategies|ServiceProviders`):

| Op | Method | Endpoint | Needs artifact? | Needs ResourceId? |
|---|---|---|---|---|
| Import | POST | `{gatewayPath}` (envelope body) | yes (exactly one) | no (id read from artifact) |
| Export | GET | `{gatewayPath}/{id}` | no | yes + `ResourceType` |
| Delete | DELETE | `{gatewayPath}/{id}` | yes (exactly one) | yes (or from artifact) |
| Enable/Disable | PUT | `{gatewayPath}/{id}/{enable\|disable}` | no | yes |
| Execute | POST | `v1/Connect/Strategies/{id}/Batch` (body `{}`) | no | yes |

**Artifact source** = exactly one of `ArtifactFile` \| `ArtifactJson` (`CanExecute` uses XOR for Import/Delete). Flow: resolve `BaseUrl`/`ApiKey` (step override or `RestClients:Connect:BaseUrl`/`ApiKey`) → load artifact (file size-guarded by `ConnEx:MaxArtifactSizeMB`, default 10, warn at 2 MB) → token-replace (`ValidateTokens` first; unresolved tokens fail unless `DryRun`) → **re-validate JSON** via `JToken.Parse` after substitution.

**ArtifactVersion re-injection** (Import only): the export transform strips envelope fields. If `artifactObj.GetValueCI(ArtifactVersion)` is null, it re-injects from `SelectTokenCI(ConfigurationArtifactVersionPath)` or `ConnExConstants.DefaultArtifactVersion` (`"1.7.1.0"`) under PascalCase `ArtifactVersion`. Uses **case-insensitive** `GetValueCI`/`SelectTokenCI` because the gateway export uses lowercase keys — a capital `Configuration` SelectToken silently missed it before.

**Credential masking** (`Helpers/ConnExArtifactMasker.MaskCredentials`): the import body's `importData` is logged **masked** (walks the tree, redacts any `assignmentType: "Credential"` value at `value.configuration.value`) — but the REAL resolved body is what's sent. Resolved DB creds never reach Seq.

**Other guards:** resource-type auto-detect from record root keys (`RecordKeyToResourceType`, case-insensitive) or explicit `ResourceType`; **path-traversal guard** on Export `OutputFile` (must resolve within the working dir); `DetectDrift` compares a new export against the existing file and records top-level key diffs in metadata; `ConnExErrorParser.TryParseErrors` parses `errors[]`/`message`/`validationErrors`/RFC-7807 `title+detail` from failure bodies; `ExpectedStatusCodes` default `[200,201,204]`; `DryRun` builds a summary and issues no HTTP call.

> **HttpClient name (FIXED — was a mismatch gotcha):** both sides now agree on `HttpClientNames.ConnEx` (`"ConnEx"`, `Logging/HttpClientNames.cs`): the executor calls `_httpClientFactory.CreateClient(HttpClientNames.ConnEx)` (`ConnExExecutor.cs` ~458) and DI registers `services.AddHttpClient(HttpClientNames.ConnEx)` (`EngineServiceCollectionExtensions.cs` ~76). The old `ConnExConstants` client-name consts (`ConnectClientName = "ConnectClient"`) were DELETED — historically the names mismatched and the client silently ran on the default unconfigured pipeline. Note the named registration is still bare (`AddHttpClient(name)` with no delegating handlers), so still do not assert the ConnEx client carries special handlers. (TestAuto's `"ConnectClient"` is a different codebase — unrelated.)

**Validation lives in two places:** the orchestrator's `ValidateConnExStep` (`Orchestration/UtilityOrchestrator.cs` ~696) runs the authoring-time `V1`–`V4`… rules (operation valid, exactly-one-artifact, non-empty `ExpectedStatusCodes`, …); the executor then repeats runtime `V10`–`V25` checks (file exists, size, unresolved tokens, JSON parse, endpoint construction). See also [[testauto-connex-service]] and [[testauto-multistep-steps]].

---

### ConnEx `WaitForBatch` — the timeout carve-out
The seventh operation blocks until a Connect batch finishes, and it has its **own** timing model because the inherited step timeout would otherwise decapitate it:

| Field | Default | Governs |
|---|---|---|
| `pollIntervalSeconds` | 30 (range 1–3600) | Gap between status polls |
| `maxWaitMinutes` | **720** (12 h) | Total wait budget for the whole loop |
| inherited `TimeoutSeconds` | 600 | **Each individual poll request only** |

Without that carve-out a 12-hour wait would be cut off after 10 minutes by the step timeout. `batchCode` bypasses strategy-name resolution; when it is absent, `ResourceId` is treated as the *strategy name* and the latest batch is resolved by `$EnterDTM`. Names and values are ported from `TestAuto.Connect` with **no** assembly reference (CrewChief takes zero TestAuto dependencies — see [[crewchief-architecture]]).

## CheckPort — `CheckPortExecutor`

A **non-mutating** assertion: read this machine's TCP listener table via the injectable
`ILocalTcpPortProbe` seam and compare it against the step's `expectation`
(`CheckPortStep.ExpectListening` / `ExpectFree`). Two behaviours are deliberate and asymmetric:

| Situation | Outcome |
|---|---|
| `targetComputer` is **not local** (`MapShareExecutor.IsLocalTarget`, `:109`) | **FAILS the step** — it refuses to answer about the wrong host rather than silently reporting on itself |
| Listener table **unreadable** (`:149`) | **SUCCEEDS** as `NOT CHECKED: port {port} could not be verified…` |

The second one looks backwards until you name what the step is for: it is a *guard*, and a guard that cannot
see must not manufacture a verdict in either direction. Failing would block a legitimate run on a
diagnostic gap; passing silently would be a lie. Saying "NOT CHECKED" out loud is the honest third answer.

> [!note] Why this is a STEP and not an eighth capability
> Preflight runs **before** the workload's Uninstall steps ([[crewchief-capability-preflight]]) — at which
> point the old instance still legitimately owns the port. A port assertion is only meaningful at a
> particular *point in the sequence*, which is exactly what a step expresses and a preflight capability
> cannot.

## Teams — `TeamsExecutor`

Posts an **Adaptive Card** wrapped in a **Power Automate Workflows** webhook envelope
(`["attachments"]`, `:188`) through the `ITeamsSender` seam. `ResolveAccentColor(severity)` (`:121`) maps the
step's severity to the card's TextBlock colour, case-insensitively.

A webhook error is a **step failure**, matching the Email step's stance rather than being swallowed as a
warning: a notification step whose whole purpose is to tell somebody something has failed silently is worse
than useless. LogTag `TEAMS` ([[crewchief-logging]]).

## WebSite — `WebSiteExecutor`

Start / Stop / Delete against IIS sites **and** web applications, addressed by the msdeploy-style
`"Site Name/AppName"` path in `sitePaths`. `"remove"` is accepted as a synonym of `Delete` (`:323`),
mirroring `ServiceControlExecutor` / `AppPoolExecutor`.

On a `Delete`, the optional `deleteAppPools` flag (`:147`) additionally cleans up **orphaned** application
pools, reporting them back (`RemovedAppPools`, `:238`). That cleanup path runs through the same
`IisBuiltInAppPools` refusal list as an explicit pool delete — see below — so an operator deleting a site
cannot take `DefaultAppPool` with it as collateral.

## Built-in protections — refusals no flag can override
`IisBuiltInAppPools` (`CrewChief.Engine/Executors/IisBuiltInAppPools.cs`) is a hard, non-bypassable refusal list of 8 pool names, deliberately **additive across OS generations** (`ASP.NET v4.0` sits alongside `.NET v4.5`), because a box may carry pools from any Windows vintage. `IsProtected(name)` is enforced on **two** paths, not one:
1. An explicit `AppPoolStep` `Delete` (`AppPoolExecutor.cs:157-166`).
2. A `WebSiteStep` delete's **orphaned-pool cleanup** — the path where an operator deleting a site could otherwise take `DefaultAppPool` with it as collateral.

Deleting a built-in pool is unrecoverable without a Windows feature repair, so this is a refusal rather than a warning. The wider "built-in protections" family (masking-before-write of run output, the 3-strike persisted secret lockout, the master-password gate on raw-JSON panes) is catalogued in the shipped doc `50_ReferenceBuiltInProtections.md`.

## HTTP vs curl — deliberately split executors

One fused HTTP step was split into two step types with two executors and separate registrations, designed **not** to shadow each other. Cross-link memory [[project_crewchief_http_curl_split]].

- **`PowerShellRestExecutor`** — `StepType "HTTP"`, handles `HttpRequestStep` (structured REST). Runs PowerShell `Invoke-RestMethod`/`Invoke-WebRequest` via a temp `.ps1` launched with `-File` (avoids the ~32K command-line limit for large bodies). Wraps the call in try/catch and `exit 1` on 4xx/5xx so the response body is captured; emits `HTTP_STATUS_CODE:` (success) / `HTTP_ERROR_STATUS:`/`HTTP_ERROR_BODY:`/`HTTP_ERROR_MESSAGE:` (error) markers. `DetermineSuccess` evaluates the **HTTP status first** (so `ExpectedStatusCodes` entries for error codes like 400/404 are reachable), then falls back to exit code. Parses CLIXML `<S S="Error">` from stderr for readable messages.
- **`CurlExecutor`** — `StepType "CURL"`, handles `CurlStep` (raw pasted curl). Token-replace the command, then run it **verbatim** via `curl.exe`:
  - `StripLeadingCurl` removes a leading `curl`/`curl.exe` token (bare args also accepted).
  - Appends `--write-out "\nHTTP_STATUS_CODE:%{http_code}"` **last** (curl honors the last `-w`, so a user `--write-out` is overridden and status parsing always works), plus `--show-error --silent`. Step-level `-o`/`--max-time` are added only if the command didn't already specify them.
  - `ParseHttpStatusCode` reads the `HTTP_STATUS_CODE:` marker; `DetermineSuccess` validates `ExpectedStatusCodes` or defaults to any 2xx (non-zero curl exit is always failure).

> Both process runners do a genuine async wait (`WaitForExitAsync(ct).WaitAsync(timeout, ct)`), kill the whole process tree on timeout/cancel, and then call the no-arg `process.WaitForExit()` to drain redirected streams (the trailing `HTTP_STATUS_CODE:` line is lost otherwise). **CurlExecutor deliberately does NOT truncate** `StandardOutput` — `RunHistoryFile` is the single truncation point (a hardcoded cap here would silently defeat `MaxStepOutputChars`). Same for **ConfigureExecutor** as of 2026-07-22: its private `Truncate` + hardcoded 10,000-char cap were removed — `RunHistoryFile`/`CrewChief:MaxStepOutputChars` (**default 100000**: `CrewChief.Web\appsettings.json:47`, `CrewChief.Cli\appsettings.json:6`, and the code fallbacks `Web\Program.cs:276`, `Cli\Program.cs:106`, `StepEditorCard.razor.cs:2084` — any `20000` you see is a stale `bin\` build artifact) is the single truncation point (the old cap silently undercut the setting, and a full Configuration.exe log easily exceeds 10K).

---

## CLU — `CLUExecutor` + `CLUCommandBuilder`

`Executors/CLUExecutor.cs`, `Services/CLUCommandBuilder.cs`, `Steps/CLUTaskType.cs`, `Steps/CLUClearOptions.cs`, `Steps/CLUConstants.cs`. Runs the Profisee Command Line Utility (`CLU.exe`).

`ICLUCommandBuilder`/`CLUCommandBuilder` both `Validate` and `BuildArguments` by switching on `CLUTaskType`: `IMPORT`, `EXPORT`, `RULES_EXPORT`, `RULES_IMPORT`, `ARCHIVEDATA`, `DEPLOYDATA`, `MATCHING_PROCESS`, `MATCHING_SURVIVORSHIP_ONLY`, `MATCHING_INDEX_REBUILD`, `MATCHING_INDEX_UNLOAD`, `MATCHING_CANCEL`.

Argument shape is **always** `TaskType -url <url> -clientid <clientId>`, then task-specific flags, then the raw `AdvancedArguments` escape hatch appended verbatim. Examples: `IMPORT` adds `-file -type [-includeMemberships] [-includeAssignments] [-reportType]`; `MATCHING_PROCESS` adds `-strategy`, then `CLUClearOptions` (a `[Flags]` enum: `CLEARPRIORRESULTS`/`CLEARALLPRIORRESULTS`/`EXCLUDEAPPROVED`/`EXCLUDEUSERMAPPED`) expand to repeated switches (`-clearPriorResults`, etc.), plus optional `-includeSurvivorship` and `-refreshinterval`.

Path and clientId come from injectable providers: `ICLUPathProvider` (`Profisee:CLU:Path`) and `ICLUClientIdProvider` (`Profisee:CLU:ClientId`). The clientId is redacted in logs/`InputText`. **Success is exit code `1`**, not 0 (`CLUConstants.ExitCodeSuccess = 1`, `ExitCodeError = 0`).

---

## SetApiKey — `SetApiKeyExecutor`

`Executors/SetApiKeyExecutor.cs` + `Steps/SetApiKeyStep.cs` + `Services/ApiKeyEncryptor.cs`. Sets a Profisee user's API credential by RSA-encrypting it and writing it straight into `meta.tUser.ClientId` — a deliberate direct DB write (the credential is the very thing needed to authenticate a REST call, and box-prep runs with the gateway down). Cross-link memory [[project_crewchief_secrets_shipped]].

- Encrypts via `IApiKeyEncryptor`/`ApiKeyEncryptor` using the platform RSA scheme; the RSA key XML is read from configuration (registered as `new ApiKeyEncryptor(configuration)`) — **never hardcoded**. `StripHyphens` (default true) mirrors the platform's `getEncryptedClientID`.
- Writes via the constant `UpdateCommandText = "UPDATE meta.tUser SET ClientId = @enc WHERE Name = @user;"` — fully parameterized (`@enc`, `@user` as `SqlParameter`s), behind the injectable `ISetApiKeySqlRunner` seam (real `DefaultSetApiKeySqlRunner`, fakeable in tests).
- **Requires exactly 1 row affected**: 1 = success; 0 = "user not found"; >1 = failure ("expected exactly 1").
- **Secret hygiene:** neither the raw key nor its ciphertext ever enters `StepExecutionResult` Output/Error/Input — `InputText` is only the parameterized statement text; the credential travels solely as a `SqlParameter`.
- **Connection model (2026-07-22 — mirrors `DatabaseOperationsStep`).** PRIMARY destination = `serverName` + `databaseName` + `authMode` (`"Windows"` default / `"Sql"`). `ResolveTargetConnectionString` builds the connection via the shared DB-ops builders — `DatabaseOperationsExecutor.BuildTrustedConnectionString` / `BuildSqlLoginConnectionString` — passing the Profisee database as the initial catalog (the builders gained an optional `string initialCatalog = "master"` param, so DB-ops behavior is unchanged). Under `Windows` auth a filled `credentialUserId`/`credentialPassword` pair runs the connection AS that account via `WindowsImpersonation.RunAsAsync` (blank pair = CrewChief service identity); `Sql` auth requires both halves. Step conveniences: `UsesSqlAuth`, `HasCredential`, and `HasTarget` (= override OR (serverName AND databaseName)) — `CanExecute` and `Validate` both use `HasTarget`.
- **`sqlDestinationConnectionSecretName` is DEMOTED to an Advanced override** that WINS when set (back-compat with older saved steps; property name retained for config compatibility). Resolution as before: a `{{...}}` token resolves directly TO the connection string (e.g. `{{$config:ConnectionStrings:ProfiseeDB}}`); a plain-text value is a legacy secret NAME resolved via ConnectionStrings/the ProfiseeAppSettings aliases — NEVER a raw connection string. When the override is set, `authMode` and the credential fields are ignored (no impersonation): `impersonate = no-override && !UsesSqlAuth && HasCredential`.
- **Validation single source of truth:** `SetApiKeyStep.GetValidationError()` — username + key + a destination, plus (serverName path only) the SQL-auth both-halves rule and the half-filled-Windows-pair rejection ("set BOTH ... or leave both blank"). The orchestrator's `SetApiKeyStep` validation case (`UtilityOrchestrator.cs` ~645) now DELEGATES to `GetValidationError()` instead of duplicating rules.
- **Destination in output/logs:** success/failure messages and log events carry "on <server>/<database>" via public static `SetApiKeyExecutor.DescribeDestination(connectionString)` — server + database only, never the raw connection string (which may carry a SQL password). Rationale: "1 row affected" is true on ANY database holding the user, so a wrong-destination run used to look identical to a correct one.

> **Operational truths (verified live on SMVM3, 2026-07-22):**
> - The new key takes effect only after restarting the Profisee (Maestro) service AND/OR IIS — the auth cache lives in BOTH. Compose `ServiceControlStep`/`IisResetStep`/`AppPoolStep` steps after SetApiKey.
> - The raw UPDATE touches ONLY `ClientId` — `LastChgDTM`/`LastChgUserID` never change, so they can NOT be used to check whether the step ran.
> - The stored blob CHANGES on every successful write (randomized PKCS#1 padding) even when re-setting the same key — that changing blob is the reliable did-it-write check.

---

## Database operations — `DatabaseOperationsExecutor` + `WindowsImpersonation`

`Executors/DatabaseOperationsExecutor.cs` + `Steps/DatabaseOperationsStep.cs` + `Executors/WindowsImpersonation.cs` + `Executors/IDatabaseCommandRunner.cs` + `Executors/DatabaseFileRelocationPlan.cs`.

**Five operations** (`Operation`, default `RestoreSnapshot`): `RestoreSnapshot` (`RESTORE ... FROM DATABASE_SNAPSHOT`, uses `snapshotName`), `BackupDatabase` (`BACKUP ... TO DISK`), `RestoreDatabase` (`RESTORE ... FROM DISK`), `CreateDatabase` (idempotent `IF DB_ID(...) IS NULL CREATE`), `DropDatabase` (idempotent — first `SET SINGLE_USER WITH ROLLBACK IMMEDIATE` to disconnect users, then `DROP`). All run against `master` on the target. Backup/restore need `backupFileName` or `fileUncPath`; create/drop need only target + `databaseName`. Snapshot restore routes through the runner's `RestoreAsync`; the other four go through `RunMasterCommandAsync` (both force `InitialCatalog = master`).

**`authMode` (`"Windows"` | `"Sql"`)** on the step selects how the `serverName` connection authenticates (ignored when `ConnectionSecretName` supplies a full connection string — that wins):

- `Windows` (default) — Windows-integrated trusted connection as the CrewChief process identity (`BuildTrustedConnectionString`). `credentialUserId`/`credentialPassword` are then *optional*: when BOTH are set, the connection runs **impersonated** as that account (see below); blank = service identity. Half-filled is rejected by validation: "set BOTH a Windows User ID and Password... or leave both blank".
- `Sql` — an explicit SQL Server login: `BuildSqlLoginConnectionString(server, userId, password)` builds a connection to **`master`** with `IntegratedSecurity = false` and `TrustServerCertificate = true` (best for a remote server where the CrewChief service's Windows machine account has no login). Validation requires both User ID and Password.

Step conveniences (`DatabaseOperationsStep.cs`): `UsesSqlAuth` (`AuthMode == "Sql"`, case-insensitive) and `HasCredential` (both credential halves non-blank), both `[JsonIgnore]`.

**`WindowsImpersonation` (static helper, ~86 lines).** The executor's decision (DatabaseOperationsExecutor.cs ~277): `impersonate = !UsesSqlAuth && HasCredential` — i.e. Windows auth *with* an explicit account. `WindowsImpersonation.RunAsAsync<T>(WindowsRunAs, Func<Task<T>>)` P/Invokes `LogonUser` with `LOGON32_LOGON_NEW_CREDENTIALS` (type 9) + `LOGON32_PROVIDER_WINNT50`, then wraps the action in `WindowsIdentity.RunImpersonatedAsync` so the impersonation **flows across awaits** — the async `SqlConnection.Open` inside the delegate authenticates as the chosen account. NEW_CREDENTIALS keeps the *local* identity unchanged and applies the credential only to **outbound** network auth (exactly the "SQL to another server as another account" case; no "Log on locally" right needed). `SplitUser` accepts `DOMAIN\user`, UPN (`user@domain`), or a bare username; a failed logon throws `Win32Exception`. Windows-only (`OperatingSystem.IsWindows()` guard at the call site).

> **Double-hop framing:** this is CrewChief's answer to the double-hop problem for *direct-from-CrewChief* connections (DB-ops SQL); for the WinRM remote-execution path the answer is instead CredSSP via `remoteAuthentication` — see [[crewchief-remote-box-prep]].

### Rename-on-restore (`relocateFiles`) — restore a backup under a *different* database name

`relocateFiles` (bool, **`RestoreDatabase` only**; ignored elsewhere) is first-class rename-on-restore — e.g. a `Profisee26R2` backup restored as `Profisee`. Without it, `RESTORE ... FROM DISK` writes the backup's *original* physical paths (colliding with the source DB if it still exists) and leaves mismatched logical names. The gate is `relocate = operation == "RestoreDatabase" && restoreStep.RelocateFiles` (executor ~332); when set, `RunRelocatingRestoreAsync` (private, ~500) does:

1. **Read the backup header** — `ReadBackupFileListAsync` runs `RESTORE FILELISTONLY FROM DISK = @disk` (**parameterized**, no literal escaping) and reads `LogicalName`/`Type` **BY NAME** (`GetOrdinal`) so the version-varying FILELISTONLY column set never breaks it. `Type == 'L'` = log, everything else treated as data.
2. **Read the server's default dirs** — `ReadDefaultFileLocationsAsync` reads `SERVERPROPERTY('InstanceDefaultDataPath'/'InstanceDefaultLogPath')` with a `sys.master_files WHERE database_id = 1` (data `type=0` / log `type=1`) directory fallback for older/default configs.
3. **`WITH MOVE`** — `BuildRelocationPlan` (pure static, unit-tested) places data files in the default *data* dir / log files in the default *log* dir, each named after the **TARGET** db: first data file `<db>.mdf`, further data `<db>_N.ndf`, log `<db>_log.ldf` (`<db>_log_N.ldf` for extra logs). `BuildRestoreDatabaseCommandWithMove` emits `RESTORE ... FROM DISK ... WITH MOVE ..., [REPLACE,] RECOVERY, STATS = 5`.
4. **Logical rename** — `BuildLogicalRenameCommand` emits `ALTER DATABASE [<db>] MODIFY FILE (NAME=<old>, NEWNAME=<new>)` per file whose logical name changed (metadata-only). Only emitted where the new name differs.

Failure semantics: a **restore failure skips the rename** (`if (!restoreResult.Succeeded || plan.Renames.Count == 0) return restoreResult`); a **rename failure surfaces its own error** while the DB is already restored (`return renameResult.Succeeded ? restoreResult : renameResult`). All three SQL calls run under the **same impersonation** as the restore — `RunRelocatingRestoreAsync` executes *inside* the `WindowsImpersonation.RunAsAsync` wrapper via the `RunAsync` local func.

### `waitIndefinitely` — infinite command timeout for hours-long restores

`waitIndefinitely` (bool, **all ops**) forces the effective SQL `CommandTimeout = 0` (infinite) over the step's `TimeoutSeconds`: `effectiveTimeout = restoreStep.WaitIndefinitely ? 0 : restoreStep.TimeoutSeconds` (~327). For legitimately multi-hour operations (e.g. a 200M-row restore). Still **cancellable** — the orchestrator's `CancellationToken` flows through, and `OperationCanceledException` propagates (never swallowed into a failed result).

### New seam methods (`IDatabaseCommandRunner`)

Beyond `RestoreAsync` / `RunMasterCommandAsync`, the runner gained `ReadBackupFileListAsync` (→ `IReadOnlyList<BackupLogicalFile(LogicalName, char Type)>`) and `ReadDefaultFileLocationsAsync` (→ `DefaultFileLocations(DataDirectory, LogDirectory)`) — both records live in `IDatabaseCommandRunner.cs`. `DefaultDatabaseCommandRunner` implements both over a shared private `OpenMasterConnection` (forces `InitialCatalog = master`, wires `InfoMessage` → Serilog, clear error on a malformed connection string). The move/rename plan (`DatabaseFileRelocationPlan` with `Moves` = `FileRelocation(LogicalName, NewPhysicalPath)` list + `Renames` = `LogicalRename(OldLogicalName, NewLogicalName)` list, `DatabaseFileRelocationPlan.cs`) is built by the pure static `BuildRelocationPlan`, keeping all path/naming logic unit-testable with zero I/O.

---

## Elevation / remote box-prep executors

`InstallExecutor`, `UninstallExecutor`, `ConfigureExecutor`, `IisResetExecutor`, `ServiceControlExecutor`, `AppPoolExecutor` (plus `ElevationStatus`, the remote transport, and credential resolution) are the machine-setup family — documented in **[[crewchief-remote-box-prep]]**.

### Configure gotcha: the exit code is meaningless (`DetectConfigurationFailure`)

Profisee `Configuration.exe` **always exits 0, even on failure**: a validation error prints `Missing parameter <name>` and an unhandled exception is logged by its outer catch as a key=value dump (`TargetSite`/`Message`/`StackTrace =`) followed by "The operation completed successfully" — then exit 0. So `ConfigureExecutor.DetectConfigurationFailure(stdout, stderr)` (public static, `ConfigureExecutor.cs` ~339) scans the combined output on BOTH exit-0 paths (local ~180, remote ~263) and fails the step when either shape appears, surfacing the missing-parameter name (regex `Missing parameter\s+(\S+)`) or the `Message =` line from the exception dump. Returns `null` = genuine success. Never trust a Configure step's exit code alone.

### Local-target rule (`MapShareExecutor.IsLocalTarget`) is FQDN-aware

The shared `IsLocalTarget` (owned by `MapShareExecutor`, delegated to by `ConfigureExecutor.IsLocalTarget` etc.) is no longer just blank/`.`/`localhost`/`127.0.0.1`/`Environment.MachineName`: a cached `Lazy` `LocalIdentities` tuple (`MapShareExecutor.cs:249-296`) holds an **exact** set (`.`, `localhost`, `127.0.0.1`, `::1`, machine name, DNS host name, FQDN) plus a **short-label** set (leading DNS label of each), and a target matches on exact OR leading-label — in **both directions**, so a short name matches the host's FQDN and a token resolving to the FQDN counts as local (no transport/credentials engaged). Callers must pass the *resolved* value. Tests: `CrewChief.Tests.Unit\Engine\IsLocalTargetTests.cs`.

## Sources
- `CrewChief\CrewChief.Engine\Steps\StepTypeRegistry.cs`
- `CrewChief\CrewChief.Engine\EngineServiceCollectionExtensions.cs`
- `CrewChief\CrewChief.Engine\Executors\SqlScriptExecutor.cs`
- `CrewChief\CrewChief.Engine\Steps\SqlStep.cs`
- `CrewChief\CrewChief.Engine\Helpers\GoBatchSplitter.cs`
- `CrewChief\CrewChief.Engine\Executors\ConnExExecutor.cs`
- `CrewChief\CrewChief.Engine\Steps\ConnExStep.cs`
- `CrewChief\CrewChief.Engine\Steps\ConnExConstants.cs`
- `CrewChief\CrewChief.Engine\Helpers\ConnExArtifactMasker.cs`
- `CrewChief\CrewChief.Engine\Helpers\ConnExErrorParser.cs`
- `CrewChief\CrewChief.Engine\Executors\CurlExecutor.cs`
- `CrewChief\CrewChief.Engine\Executors\PowerShellRestExecutor.cs`
- `CrewChief\CrewChief.Engine\Services\CLUCommandBuilder.cs`
- `CrewChief\CrewChief.Engine\Executors\CLUExecutor.cs`
- `CrewChief\CrewChief.Engine\Steps\CLUTaskType.cs`, `CLUClearOptions.cs`, `CLUConstants.cs`
- `CrewChief\CrewChief.Engine\Executors\SetApiKeyExecutor.cs`
- `CrewChief\CrewChief.Engine\Steps\SetApiKeyStep.cs`
- `CrewChief\CrewChief.Web\Documentation\26_StepGuideSetApiKey.md`
- `CrewChief\CrewChief.Engine\Logging\HttpClientNames.cs`
- `CrewChief\CrewChief.Engine\Orchestration\UtilityOrchestrator.cs` (`ValidateConnExStep`)
- `CrewChief\CrewChief.Engine\Executors\DatabaseOperationsExecutor.cs`
- `CrewChief\CrewChief.Engine\Steps\DatabaseOperationsStep.cs`
- `CrewChief\CrewChief.Engine\Executors\WindowsImpersonation.cs`
- `CrewChief\CrewChief.Engine\Executors\IDatabaseCommandRunner.cs` (runner seam + `BackupLogicalFile`/`DefaultFileLocations`/`ReadBackupFileListAsync`/`ReadDefaultFileLocationsAsync`)
- `CrewChief\CrewChief.Engine\Executors\DatabaseFileRelocationPlan.cs` (`DatabaseFileRelocationPlan`/`FileRelocation`/`LogicalRename`)
- `CrewChief\CrewChief.Engine\Executors\ConfigureExecutor.cs` (`DetectConfigurationFailure`)
- `CrewChief\CrewChief.Engine\Executors\MapShareExecutor.cs` (`IsLocalTarget`, `LocalIdentities`)
- `CrewChief\CrewChief.Tests.Unit\Engine\IsLocalTargetTests.cs`
