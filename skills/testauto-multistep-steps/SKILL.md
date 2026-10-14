---
name: testauto-multistep-steps
description: >
  MultiStepUtilityScenario step type reference for TestAuto. Use when writing a step JSON config,
  choosing a step type, configuring SQL/HTTP/PowerShell/CLU/ConnEx/Monitor/CommandLine steps, token
  replacement ({{...}}, {{$env:}}, {{$config:}} — one source per token, no fallback), inline step
  content (sqlScript/scriptContent/body/command), UseRestMethod, HTTP step timeouts (MaxTimeSeconds vs
  TimeoutSeconds and the process-kill grace), the sqlSourceConnectionSecretName /
  sqlDestinationConnectionSecretName pair, UseShell, DDL transaction limits,
  TreatStderrAsError, or ExpectedStatusCodes.
---

# MultiStepUtilityScenario — Step Type Guide

> **Scope**: speed-merchants (TestAuto.Utilities + TestAuto.Web)
> **Source**: TestAuto.Web/Documentation/StepGuide_Index.md + individual step guides

A **MultiStepUtilityScenario** executes a JSON-defined sequence of steps in order. Each step has a `Type` field that selects the executor. Steps run sequentially; failure stops the sequence unless `ContinueOnError` is true.

---

## Reference files (load on demand)

This file carries the decision rules, defaults, and gotchas. The catalogs live in
`references/` and cost nothing until you read one.

| File | Read it when |
|---|---|
| `references/per-step-json-reference.md` | You need the complete property list or a full JSON example for one step type |
| `references/clu-task-types.md` | Filling in a CLU step's `Parameters`, or a CLU step fails on credentials |
| `references/utility-runner.md` | Standing up a utility-runner project, or a run fails for non-step-specific reasons |
| `references/authoring-and-files.md` | Adding a step type, plugin build issues, or working with `.curl` / body files |
| `references/connex-telemetry.md` | Interpreting ConnEx step output or querying `ConnExStepDetail` |
| `references/sources.md` | You want the underlying source-file list |

---

## Step Types at a Glance

| Step Type | Type Value(s) in JSON | What It Does | When to Use |
|---|---|---|---|
| **HTTP Request** | `"HttpRequestStep"`, `"CURL"`, `"Http"` | HTTP/HTTPS REST calls | API calls, Profisee REST operations |
| **SQL** | `"SqlStep"`, `"SQL"` | SQL scripts against SQL Server | Queries, data setup/teardown, migrations |
| **PowerShell** | `"PowerShellStep"`, `"Powershell"`, `"PS"` | Run PowerShell scripts | System checks, file operations, automation |
| **Command Line** | `"CommandLineStep"`, `"CommandLine"`, `"CLI"`, `"CMD"` | Execute command-line programs | Ping, file ops, external tools |
| **CLU** | `"CLUStep"`, `"CLU"` | Profisee Command Line Utility | Import/export data, deploy rules, run matching |
| **ConnEx** | `"ConnExStep"`, `"ConnEx"` | Manage ConnEx integration artifacts | Import/export service configs |
| **Monitor** | `"MonitorStep"`, `"Monitor"` | Publish a monitor activity message | Logging milestones, audit trail |

> Type value is **case-insensitive**: `"SqlStep"` = `"sqlstep"` = `"SQL"`.

---

## Token Replacement

Three kinds of tokens are replaced before each step executes:

### 1. Custom tokens — `{{TokenName}}`
Defined in `GlobalParameters` (shared) or step-level `Parameters` (overrides global):
```json
{
  "GlobalParameters": { "ServerName": "corpltr94" },
  "Steps": [{ "Type": "CURL", "Url": "https://{{ServerName}}.corp.profisee.com/rest" }]
}
```

### 2. Environment variable tokens — `{{$env:VariableName}}`
Reads from machine environment at runtime:
```json
{ "Url": "https://{{$env:PROFISEE_HOST}}/profisee/REST/records" }
```

> **Important**: The prefix is `$env:`, not `ENV:`. Using `{{ENV:VariableName}}` will be treated as a regular parameter key (not an env var) and will fail with a missing-token error if no parameter named `ENV:VariableName` exists.

### 3. Configuration tokens — `{{$config:Section:Key}}`
Reads from `appsettings.json` or user secrets at runtime. Use for API keys/URLs:
```json
{
  "Url": "{{$config:RestClients:Profisee:BaseUrl}}rest/v1/Matching/strategies",
  "Headers": { "x-api-key": "{{$config:RestClients:Profisee:ApiKey}}" }
}
```

### Resolution is **prefix-driven**, not a precedence chain

A common misreading is that the four sources form a fallback chain. They do not. `TextTemplater.ResolveTokenValue` (`TextTemplater.cs:110-133`) dispatches on the token's **prefix** and consults **exactly one source**:

| Token shape | Sole source consulted | If absent there |
|---|---|---|
| `{{$config:Section:Key}}` | `IConfiguration` | unresolved — **never** falls back to a parameter named `$config:Section:Key` |
| `{{$env:VAR}}` | `Environment.GetEnvironmentVariable` | unresolved — never falls back to parameters |
| `{{AnythingElse}}` | the merged parameters dictionary | unresolved — never falls back to config or env |

Prefix matching is `OrdinalIgnoreCase`, so `{{$CONFIG:...}}` works. The class doc states the order as "special prefixes first, then parameters" (`TextTemplater.cs:21`), but that is *dispatch* order within one token, not cross-source precedence.

**The only real precedence is between the two parameter sources**, and it is applied *before* the templater ever runs: `UtilityOrchestrator` (`UtilityOrchestrator.cs:171-180`) copies `GlobalParameters` into a case-insensitive dictionary and then overwrites with the step's own `Parameters` — *"step parameters take precedence over global"*. By the time `TextTemplater` sees them there is one flat dictionary.

**Unresolved tokens fail the step, they do not pass through.** `ReplaceTokens` calls `ValidateTokens` first and throws `ArgumentException` listing **every** unresolvable token at once (`TextTemplater.cs:81-87`). One asymmetry in `CanResolveToken` (`:202-225`): a `$config:`/`$env:` token must resolve to a **non-empty** value to count as resolvable, whereas a plain parameter token only needs its **key to exist** — a parameter explicitly set to `""` resolves fine.

---

## Common Step Properties (UtilityStepBase)

Every step type inherits these:

| Property | Type | Default | Description |
|---|---|---|---|
| `Type` | string | _(required)_ | Step type identifier |
| `Description` | string | `null` | Logged during execution |
| `Parameters` | Dictionary | `{}` | Step-specific token values |
| `TimeoutSeconds` | int | `600` | Max execution time (10 min default) |
| `ContinueOnError` | bool | `false` | Continue scenario if this step fails |
| `WorkingDirectory` | string | `null` | Override working dir for this step |
| `RetryEnabled` | bool | `false` | When `true`, retry a failed attempt |
| `MaxRetries` | int | `0` | Additional retry attempts, clamped 0–10; total attempts = `1 + MaxRetries` |
| `RetryDelaySeconds` | int | `5` | Delay between attempts, clamped 0–300 |

> **Retry vs ContinueOnError ordering**: `UtilityOrchestrator` exhausts retries **first** —
> `maxAttempts = RetryEnabled ? 1 + Math.Clamp(MaxRetries, 0, 10) : 1`, sleeping
> `Math.Clamp(RetryDelaySeconds, 0, 300)` between attempts. Only after every attempt has
> failed is `ContinueOnError` evaluated to decide whether the scenario stops or continues.

### Inline content only

Step content is **always inline** in the JSON. File/script-path references (`ScriptKey`, `BodyFilePath`, `ScriptPath`) have been **retired** — the executors and DTOs no longer read content from disk. Each step type carries its content in a dedicated inline field:

| Step type | Inline content field |
|---|---|
| SQL | `sqlScript` |
| PowerShell | `scriptContent` |
| HTTP | `body` |
| CommandLine | `command` (+ `args`) |

> Legacy configs that still carry a `bodyFilePath` are inlined into `body` by the one-time conversion job (see [[testauto-config-store-migration]]); a stray `scriptKey` can't be inlined and must be re-authored. There is no runtime fallback to a file.

---

## SQL Step (`SqlStep` / `SQL`)

**Executor**: `SqlScriptExecutor` | **DTO**: `SqlStep`

> **Note**: Uses `Microsoft.Data.SqlClient` directly (not `SqlHelper`) to support InfoMessage event handling, `GO` batch splitting, and infinite timeout. This is intentional.

| Property | Type | Default | Description |
|---|---|---|---|
| `SqlScript` | string | `null` | Inline SQL — the only content source. `GO` batch separators **are** supported (split via `GoBatchSplitter`). |
| `sqlSourceConnectionSecretName` | string | `""` | Secret name for the **read** connection (used with SELECT / `CaptureScalarResult`) |
| `sqlDestinationConnectionSecretName` | string | `""` | Secret name for the **write** connection (used for all other batches) |
| `SqlCommandTimeoutSeconds` | int | `600` | Command-level timeout. Set `0` for infinite. |
| `UseTransaction` | bool | `true` | **Must be `false` for DDL** — CREATE DATABASE, ALTER DATABASE, BACKUP, DBCC, full-text operations cannot run inside a transaction |
| `CaptureScalarResult` | bool | `false` | Capture the first batch's scalar return value using the source connection |
| `AutoWrapPassFailCode` | bool | `true` | Wrap script in TRY/CATCH; step exits 0 (pass) or 1 (fail) |
| `SqlAllowNonTransactionalBatches` | bool | `false` | Allow fallback to non-transactional execution on error |

Scripts are split on `GO` statements and executed as separate batches. Source connection is used when `CaptureScalarResult = true`; destination otherwise.

### SQL Gotchas

- **`GO` batch separation works on the inline `SqlScript`.** `SqlScriptExecutor` runs `GoBatchSplitter.SplitBatches` on the script content unconditionally, so `GO` is honored in inline SQL.
- **Source vs destination split** prevents accidental writes through a read-only connection. Use `sqlSourceConnectionSecretName` for queries, `sqlDestinationConnectionSecretName` for INSERT/UPDATE/DELETE/DDL. Those are the exact JSON names (`SqlStep.cs:17`, `:26`) — camelCase, `...ConnectionSecretName`, no `ConnectionString` property exists on the step.
- **Both secret names are mandatory, even for a read-only step.** `SqlScriptExecutor.CanExecute` returns false unless **both** are non-empty (`SqlScriptExecutor.cs:70-71`); leave one blank and no executor claims the step. Set both to the same secret when there is only one database.
- **How a secret name resolves** (`SqlScriptExecutor.ResolveConnectionString`, `:247-266`), in order: `IConfiguration.GetConnectionString(name)` → `ConnectionStrings:{name}` → a legacy `ProfiseeAppSettings` fallback. The legacy fallback fires for exactly three **case-sensitive (`StringComparison.Ordinal`)** names — `"ProfiseeDB"`, `"MessagingDB"`, `"MonitorDB"` (`SqlConnectionStringSecretAliases` in `TestAuto.Shared/Constants/ProfiseeAppSettingsConfigurationKeys.cs:19-26`) — mapping to `ProfiseeAppSettings:ProfiseeDBConnection` / `:MessagingDBConnection` / `:MonitorDbConnection`. Casing matters: `"profiseedb"` will **not** hit the fallback. Anything unresolvable throws with the offending secret name in the message.
- **DDL requires `UseTransaction: false`**. Operations like `CREATE DATABASE`, `ALTER DATABASE`, `BACKUP`, `DBCC`, and full-text operations throw an error if wrapped in a transaction.
- **`CaptureScalarResult`** requires the first batch to return at least one row. A null result (no rows) is a common runtime error; ensure the query has data before enabling this.

---

## HTTP Request Step (`HttpRequestStep` / `CURL` / `Http`)

**Executor**: `PowerShellRestExecutor` — handles all HTTP/CURL steps.

> **Note**: Both `CurlExecutor` and `PowerShellRestExecutor` register for `StepType = "CURL"`. DI registers `CurlExecutor` first, then `PowerShellRestExecutor`; the orchestrator dictionary keeps the last registration, so **`PowerShellRestExecutor` always handles CURL/HTTP steps**. Do not add a third executor with the same StepType without reconciling this.

| Property | Type | Default | Description |
|---|---|---|---|
| `Url` | string | _(required)_ | Target URL (supports tokens) |
| `Method` | string | `"GET"` | HTTP method: GET, POST, PUT, PATCH, DELETE, HEAD, OPTIONS |
| `Headers` | Dictionary | `{}` | Request headers |
| `Body` | string | `null` | Request body (inline JSON/text) — the only body source |
| `OutputFile` | string | `null` | Save response body to file |
| `ExpectedStatusCodes` | int[] | `[]` | Success codes. **Empty = any 2xx**. Single code: `[200]`. Multiple: `[200, 204]`. |
| `FollowRedirects` | bool | `true` | Follow 3xx responses |
| `VerifySsl` | bool | `true` | Set `false` for self-signed certs in dev/test |
| `MaxTimeSeconds` | int? | `null` → **`TimeoutSeconds`** | Inner per-request timeout. Falls back to the step's own `TimeoutSeconds` — see below. |
| `UseRestMethod` | bool | `true` | Selects the generated command: `true` = PowerShell `Invoke-RestMethod`; `false` = `curl.exe`. See below. |

### `MaxTimeSeconds` falls back to `TimeoutSeconds` — the 30 s hardcode is GONE

> [!note] This reversed in 2026-08
> Earlier revisions of this skill (correctly, at the time) warned that the DTO's XML doc was lying: the doc
> said "If not specified, uses the step's `TimeoutSeconds` value" while the code emitted a hardcoded
> `?? 30`. **The code was fixed to match the doc.** The comment is now accurate and the 30 s trap no longer
> exists. `HttpRequestStep.cs:183` even records the change: *"previously fell back to a hardcoded 30,
> ignoring TimeoutSeconds"*.

```csharp
// HttpRequestStep.cs:184 — the INNER request timeout
lines.Add($"  -TimeoutSec {(MaxTimeSeconds ?? TimeoutSeconds)}");
```

The outer process-kill bound is no longer `TimeoutSeconds * 1000` either. It is computed by
`HttpStepTimeoutCalculator.ResolveProcessKillTimeoutSeconds` (`TestAuto.Utilities/Helpers/HttpStepTimeoutCalculator.cs:40`):

```
max(TimeoutSeconds, MaxTimeSeconds ?? 0) + ProcessKillGraceSeconds   // grace = 5
```

Consumed by `PowerShellRestExecutor.cs:312` and `CurlExecutor.cs:333`.

**Why the grace margin exists:** if the outer kill were bounded by `TimeoutSeconds` alone, a step with
`MaxTimeSeconds > TimeoutSeconds` would have its process murdered *before* the inner timeout could fire —
the caller would see a killed process instead of a clean, diagnosable "the request timed out". The margin
covers interpreter start-up (a cold `powershell.exe` costs a second or two before the inner clock even
begins), the wrapped script's error-handling tail, and redirected-stream drain, so the **inner timeout
always wins the race** and produces the better error. `ResolveProcessKillTimeoutMs` clamps at `int.MaxValue`
so an absurd configured timeout cannot overflow into a negative (immediate-kill) value.

**Practical rule:** set `MaxTimeSeconds` only when you want the request bounded *tighter or looser* than the
step itself. Leaving it unset is now the correct default, not a trap.

The curl branch also appends `--max-time` only when `MaxTimeSeconds.HasValue` (`CurlExecutor.cs:249-251`),
so curl uses its own default when unset.

### The server's error body — `StepExecutionResult.HttpResponseBody`

A failing HTTP/CURL step now captures the server's **own** error payload
(`StepExecutionResult.cs:120-134`) — an ASP.NET `ValidationProblemDetails` naming the offending field, or a
Profisee gateway code such as `10051`. Without it the caller only ever saw PowerShell's generic
*"The remote server returned an error: (400) Bad Request."*, which names neither the field nor the reason.

> [!note] Held in memory, deliberately NOT persisted
> It feeds logging and the composed `ErrorMessage`, but is **not** projected into the persisted metric
> detail — that would need a new Profisee attribute subject to the **4000-character value ceiling**
> ([[reference_scenariodatadisplay_4000_ceiling]]). It is the HTTP analogue of `PassFailErrorDetail`.

### Semantic-status reconciliation — when the transport code lies

The gateway can return a **transport 400** whose body declares something else entirely:

```json
{"status": 404, "detail": "Service Configuration not found"}
```

So when the transport code is not in `ExpectedStatusCodes`, the executor re-checks the **body's** declared
status via `ConnExErrorParser.TryGetSemanticStatusCodes(body)` (`:64`) before failing the step. A delete
step that legitimately tolerates "already gone" therefore works even when the gateway wraps the 404 in a
400.

Two related guards:

- **Whitelisting any code `>= 400` now emits a warning.** Suppressing a real failure should be a visible
  decision, not a quiet config line.
- **A 207 multi-status body with per-item failures fails the step.** (Currently inert under
  `Invoke-RestMethod`, which reports no status on success — it bites on the curl path.) See
  [[feedback_207_not_success]].

### `UseRestMethod` — Invoke-RestMethod vs curl

`UseRestMethod` (`HttpRequestStep.cs:93`, default **`true`**) selects which command `GenerateExecutionCommand` produces (`:105`):

| Value | Generated command | Notes |
|---|---|---|
| `true` (default) | PowerShell `Invoke-RestMethod` via `GeneratePowerShellRestCommand` | PowerShell-native; the `-TimeoutSec {MaxTimeSeconds ?? TimeoutSeconds}` fallback above applies |
| `false` | `curl.exe` command line via `GenerateCurlCommand` | `PowerShellRestExecutor.cs:61-62` branches to the curl path; `CustomCurlArgs` is appended here |

This is a **per-step** switch inside the one executor — it is *not* the same thing as the `CurlExecutor`-vs-`PowerShellRestExecutor` DI-registration quirk noted above. `PowerShellRestExecutor` always wins the `CURL` StepType registration; `UseRestMethod` then decides what it emits. Set `UseRestMethod: false` when you need a curl-only flag via `CustomCurlArgs`, or when curl's HTTP behavior (redirect/proxy/TLS handling) is what you are actually trying to exercise.

### HTTP Gotchas

- **`ExpectedStatusCodes` is a list**, not a single value (`ExpectedStatusCode` is the old single-value form). Use `[200, 201]` for POST endpoints that may return either.
- Profisee REST record creation requires `"Content-Type": "application/json-patch+json"` (not `application/json`).
- Delete/cleanup steps often return 204 on success and 404 if already deleted — use `ExpectedStatusCodes: [200, 204, 404]` with `ContinueOnError: true` to make them idempotent.
- **`ExpectedStatusCodes` with error codes (e.g. `[404]`, `[400]`) works even though the step "failed" at the process level.** `PowerShellRestExecutor` evaluates the **HTTP status code before the process exit code** when deciding success: the PS-REST wrapper deliberately `exit 1`s on a 4xx/5xx so it can still capture the response body, and the executor honors `ExpectedStatusCodes` against the captured HTTP status rather than short-circuiting on the non-zero exit. So a "delete when it does not exist" step with `ExpectedStatusCodes: [404]` passes cleanly.

---

## PowerShell Step (`PowerShellStep` / `PS`)

**Executor**: `PowerShellScriptExecutor`

| Property | Type | Default | Description |
|---|---|---|---|
| `ScriptContent` | string | `null` | Inline PowerShell script — the only content source |
| `ExecutionPolicy` | string | `"Bypass"` | Restricted, AllSigned, RemoteSigned, Unrestricted, **Bypass**, Undefined |
| `PreferWindowsPowerShell` | bool | `false` | `false` = try pwsh first, fall back to powershell.exe; `true` = powershell.exe only |
| `RunAsAdministrator` | bool | `false` | Elevated privileges |
| `CaptureVerbose` | bool | `false` | Add `-Verbose` flag to invocation |
| `CaptureDebug` | bool | `false` | Add `-Debug` flag to invocation |
| `TreatStderrAsError` | bool | `true` | **Fail step if stderr has any output** — some scripts write to stderr without failing; set `false` when needed |
| `EnvironmentVariables` | Dictionary | `null` | Env vars for the PowerShell process |
| `SuccessExitCodes` | int[] | `null` | null/empty = only exit code 0 is success |

### PowerShell Gotchas

- **`TreatStderrAsError` defaults to `true`** — this catches real errors but also catches warnings that many standard cmdlets emit to stderr. Set `false` if the script is known to write harmless warnings.
- **Core vs Windows PowerShell**: `pwsh` (Core) is cross-platform but lacks AD, COM, and legacy Windows modules. Set `PreferWindowsPowerShell: true` if you need Active Directory (`Get-ADUser`) or other Windows-only modules.
- Token replacement in script content is **case-insensitive** on keys but whitespace-sensitive around `{{` and `}}`.

---

## Command Line Step (`CommandLineStep` / `CLI` / `CMD`)

**Executor**: `CommandLineExecutor`

| Property | Type | Default | Description |
|---|---|---|---|
| `Command` | string | _(required)_ | Executable name (resolved via PATH) or absolute path |
| `Args` | string[] | `[]` | Arguments — **each element = one argument; spaces within an element are preserved** |
| `UseShell` | bool | `false` | **Must be `true`** for pipes (`\|`), redirects (`>`), shell operators (`&&`, `\|\|`) |
| `ShellPath` | string | `null` | Custom shell; defaults to `cmd.exe` (Windows) or `/bin/sh` |
| `EnvironmentVariables` | Dictionary | `null` | Env vars for the child process |
| `WorkingDirectory` | string | `null` | Override working directory |
| `RedirectStandardInput` | bool | `false` | Enable stdin injection |
| `StandardInput` | string | `null` | Content to write to stdin |
| `SuccessExitCodes` | int[] | `[0]` | **Tool-specific** — robocopy uses 0–3 for success; findstr uses 1 for "no match" |
| `WaitForExit` | bool | `true` | Set `false` for fire-and-forget (metrics won't capture exit code) |
| `CreateNoWindow` | bool | `true` | Windows only — hide console window |

### CommandLine Gotchas

- **Shell features require `UseShell: true`** or wrap in `cmd /c "..."`. Pipes, redirects, `&&`, and `||` are interpreted by the shell, not the executable. Without `UseShell: true` they are passed as literal arguments to the target process.
- **Each `Args` element = one argument** — no additional quoting needed. `["--path", "<a folder with spaces>"]` passes two arguments correctly.
- **robocopy**: exit codes 0–3 indicate success; code 8+ is an error. Always set `SuccessExitCodes: [0, 1, 2, 3]`.
- **findstr / grep**: exit code 1 means "no matches found" (not an error for many use cases). Set `SuccessExitCodes: [0, 1]` if absence of a match is acceptable.

---

## CLU Step (`CLUStep` / `CLU`)

**Executor**: `CLUExecutor` — runs the Profisee Command Line Utility.

CLU path and ClientId come from secrets: `Profisee:CLU:Path` and `Profisee:CLU:ClientId`. Configure these in the `/secrets` UI; verify via the **CLU Secrets Status Panel** in the scenario editor (green badge = configured, red = missing).

### Common CLU Properties (all TaskTypes)

| Property | Type | Default | Description |
|---|---|---|---|
| `Url` | string | _(required)_ | Profisee instance base URL |
| `TaskType` | string | _(required)_ | One of the 11 task type strings (see table below) |
| `TimeoutSeconds` | int | `600` | Maximum execution time (CLU matching can take hours — use 7200+ for large strategies) |
| `ContinueOnError` | bool | `false` | Continue scenario if CLU step fails |
| `AdvancedArguments` | string | `null` | Raw args appended verbatim to the CLU command — not validated |

### TaskType Reference

| TaskType | Required | Optional | Notes |
|---|---|---|---|
| `IMPORT` | `FilePath`, `TypeHint` | `ReportType`, `IncludeMemberships`, `IncludeAssignments` | TypeHint: ALL / MODEL / APPLICATION / DATA / RULES |
| `EXPORT` | `FilePath`, `TypeHint` | `ReportType` | Same TypeHint values as IMPORT |
| `RULES_EXPORT` | `FilePath`, `Entity` | — | Exports XML business rules for a specific entity |
| `RULES_IMPORT` | `FilePath` | — | Imports business rules from an XML file |
| `ARCHIVEDATA` | `Strategy` | — | Runs a named archiving strategy |
| `DEPLOYDATA` | `FilePath` | — | Deploys a data package |
| `MATCHING_PROCESS` | `Strategy` | `ClearOptions`, `IncludeSurvivorship`, `RefreshIntervalMs` | ClearOptions: CLEARPRIORRESULTS / CLEARALLPRIORRESULTS / EXCLUDEAPPROVED / EXCLUDEUSERMAPPED |
| `MATCHING_SURVIVORSHIP_ONLY` | `Strategy` | `RefreshIntervalMs` | Runs survivorship without re-matching |
| `MATCHING_INDEX_REBUILD` | `Strategy` | — | Rebuilds the matching index for a strategy |
| `MATCHING_INDEX_UNLOAD` | `Strategy` | — | Unloads the matching index from memory |
| `MATCHING_CANCEL` | `Strategy` | — | Cancels a running or queued matching operation |

---

## CLU Task Type Parameters — Full Reference

Per-TaskType parameter tables (IMPORT, EXPORT, RULES_EXPORT, RULES_IMPORT,
ARCHIVEDATA, DEPLOYDATA, MATCHING_PROCESS, MATCHING_SURVIVORSHIP_ONLY,
MATCHING_INDEX_*), timeout recommendations, and CLU secrets configuration
(JSON import, Web UI edit, verification, troubleshooting):
**`references/clu-task-types.md`**.

Read it when writing or debugging a CLU step's `Parameters` block, or when a
CLU step fails on credentials. The TaskType selection table above is enough to
pick a TaskType; the reference is for filling in its parameters.

---
## Utility Runner Onboarding

Minimal config JSON, project layout, core concepts, the inline-content rule,
plus the pattern catalog, troubleshooting table, debugging tips, and best
practices: **`references/utility-runner.md`**.

Read it when standing up a new utility-runner project or when a run fails for
reasons that are not step-type specific.

---
## ConnEx Step (`ConnExStep` / `ConnEx`)

**Executor**: `ConnExExecutor` — manages ConnEx integration artifacts (Import/Export/Delete/Enable/Disable/Execute). Supports `{{token}}` replacement inside artifact JSON content before the HTTP call.

> **Full examples**: see [Per-Step JSON Configuration Reference — ConnEx Step](#connex-step-connexstep--connex-1) below.

| Property | Type | Default | Description |
|---|---|---|---|
| `ArtifactFile` | string | `null` | Path to artifact JSON file, relative to `WorkingDirectory` (XOR with `ArtifactJson`). Supports tokens. |
| `ArtifactJson` | string | `null` | Inline artifact JSON (XOR with `ArtifactFile`). Supports tokens. |
| `ResourceType` | string | auto-detected | `"ServiceConfiguration"`, `"IntegrationStrategy"`, or `"ServiceProvider"`. Auto-detected from artifact root key if absent. |
| `Operation` | string | `"Import"` | `"Import"`, `"Export"`, `"Delete"`, `"Enable"`, `"Disable"`, `"Execute"`. |
| `ResourceId` | string | `null` | Target resource GUID for Export/Delete/Enable/Disable. Auto-read from artifact `.Id` field for Delete if absent. |
| `OutputFile` | string | `null` | File path to write Export response (directories created as needed). |
| `DryRun` | bool | `false` | Validates token replacement, artifact parse, and URL resolution but does NOT call the HTTP API. Returns diagnostic summary. |
| `ReturnResult` | bool | `true` | Request the imported object back in the API response. |
| `ExpectedStatusCodes` | int[] | `[200, 201, 204]` | Override expected success codes. Import → 201; Export → 200; Enable/Disable → 204. |
| `BaseUrl` | string | from config | Override `RestClients:Connect:BaseUrl`. |
| `ApiKey` | string | from config | Override `RestClients:Connect:ApiKey`. |
| `SkipFileWrite` | bool | `false` | For Export: skip writing to `OutputFile` (response still captured in step result). |

### Three-Resource Ordering Rule

When a scenario needs to set up ConnEx from scratch, **always import in this order**:
1. `ServiceProvider` — must exist before service configurations reference it
2. `ServiceConfiguration` — must exist before strategies reference it
3. `IntegrationStrategy` — references both above

Reversing this order produces 400/422 errors from the Connect API.

### Scripts/ConnEx Artifact Template Library

Pre-built artifact JSON templates live in `TestAuto.Utilities/Scripts/ConnEx/`. Each file is a live-provider export with `{{token}}` placeholders for credentials and environment-specific values.

**Naming convention**: `{Provider}.{AuthScheme}.{ResourceType}.json`

| Provider | Available Templates |
|---|---|
| `SqlServer` | ServiceProvider, ServiceConfiguration, IntegrationStrategy (import/export) |
| `Databricks` | ServiceProvider, ServiceConfiguration |
| `Snowflake` | ServiceProvider, ServiceConfiguration |
| `Synapse` | ServiceProvider, ServiceConfiguration |
| `OneLake` | ServiceProvider, ServiceConfiguration |
| `Profisee` | ServiceProvider, ServiceConfiguration |
| `File` | ServiceProvider, ServiceConfiguration |

**Tip**: Use `DryRun: true` to validate token replacement against a template before the first real deployment run.

**Note on Strategy mapping templates**: strategy templates in the library intentionally have empty field mappings — you must export a live strategy from a configured instance and replace the template, or populate the mappings manually.

### Enable / Disable / Execute Operations

These three operations require `ResourceId` — there is no artifact source to extract it from.

| Operation | HTTP | Endpoint pattern | ResourceId value |
|---|---|---|---|
| `Enable` | PUT | `v1/Connect/Strategies/{id}/enable` | Strategy name or GUID |
| `Disable` | PUT | `v1/Connect/Strategies/{id}/disable` | Strategy name or GUID |
| `Execute` | POST | `v1/Connect/Strategies/{id}/Batch` | Strategy name or GUID |

`Execute` sends `{}` as the body and triggers a ConnEx batch run — equivalent to clicking "Run" in the ConnEx portal. It does **not** require `ArtifactFile` or `ArtifactJson`.

```json
{
  "Type": "ConnEx",
  "Description": "Run nightly import strategy",
  "Operation": "Execute",
  "ResourceId": "SQL_Server_ModelSource_Import",
  "ExpectedStatusCodes": [200, 202]
}
```

### Artifact Size Limits

The executor enforces size checks before sending the HTTP request:

| Limit | Value | Configurable via |
|---|---|---|
| Hard maximum | 10 MB | `ConnEx:MaxArtifactSizeMB` in appsettings/secrets |
| Warning threshold | 2 MB | hardcoded — logged as warning, not failure |

Size is checked both before and after `{{token}}` replacement (expanded tokens like base64 credentials can push an artifact over the limit after replacement). Exceeding the hard max returns a failure result without calling the API.

- **The pre-replacement check only runs for `ArtifactFile`** — hard max and the 2 MB warning are evaluated when the file is loaded. Inline `ArtifactJson` skips the pre-check and is only size-checked after token replacement.
- Constants live in `ConnExConstants`: `MaxArtifactSizeMBConfigKey = "ConnEx:MaxArtifactSizeMB"`, `DefaultMaxArtifactSizeMB = 10`, `ArtifactWarningSizeMB = 2` (warning is a hardcoded const, not configurable). A non-numeric or negative config value silently falls back to the 10 MB default.

### Run-Time Description Resolution

The step `Description` may itself contain tokens (`{{Param}}`, `{{$config:...}}`). `ConnExExecutor.ResolveDescriptionForLog` resolves them at **execution time** and uses the resolved text for log lines and the result `StepKey` — e.g. `"Import {{$config:ServerNames:DatabaseServerName}}_ModelSource"` shows up as `"Import SMVMDB3_ModelSource"` in logs and step results.

- Resolution is **best-effort**: if any token can't be resolved, the raw templated description is kept — it's only a label, never a step failure. An empty `Description` falls back to `"ConnEx"`.
- This is why `ConnExScenarioFactory` stores the step `Description` templated (resolving the scenario `DisplayName` separately at creation time): the same step text shows the right server name on whichever environment it executes.

### Inline ArtifactJson vs ArtifactFile

`ArtifactJson` on generated import scenarios is produced by the import-time tokenizer flow + `ConnExScenarioFactory` (TestAuto.Web): the token-selection dialog yields a `{{token}}`-templated artifact, which the factory embeds **inline** in the step and stores with the scenario config.

- **Inline is preferred when it fits** — the artifact travels with the scenario (portable across machines, no stray on-disk file). The factory only falls back to saving the artifact via `IConnExArtifactStorage` and setting `ArtifactFile` when the compressed scenario data exceeds the 4,000-character attribute limit (`MaxCompressedScenarioChars`).
- If the scenario still doesn't fit after externalizing the artifact, creation fails with a size error.
- For `Import`/`Delete`, the executor requires **exactly one** of `ArtifactFile` / `ArtifactJson` (XOR) — setting both (or neither) means no executor accepts the step.

### Export — Drift Detection

When `Operation` is `Export` and `OutputFile` already exists, the executor compares the live response to the local file using `JToken.DeepEquals`. If they differ, it logs a warning and populates `ConnExStepDetail` with:

- `DriftDetected: true`
- `DriftSummary`: human-readable list of differing top-level JSON keys and size delta

The step still **succeeds** — drift is reported, not failed. Use it to detect configuration drift between environments or to verify export round-trips.

### ConnExStepDetail Telemetry and API Path Systems

Per-detail telemetry fields, what gets recorded on each ConnEx operation, and
the two API path systems: **`references/connex-telemetry.md`**.

Read it when interpreting ConnEx step output or building a query over
`ConnExStepDetail`.

---
## Monitor Step (`MonitorStep` / `Monitor`)

**Executor**: Posts a monitor activity via `IMonitorActivityWriter` (NServiceBus).

> **Note**: Monitor uses NServiceBus `LogManager`, not Serilog. Quieting its log messages is an NServiceBus log-level concern, not a Serilog source-context filter.

| Property | Type | Default | Description |
|---|---|---|---|
| `Message` | string | _(required)_ | Monitor activity message text (supports `{{token}}` replacement) |

> `ActivityType` is not a top-level property — set it via the `Parameters` dictionary (key `"ActivityType"`). See the [per-step Monitor reference](#monitor-step-monitorstep--monitor-1) below.

---

## Execution Flow

```
1. Parse "Steps" array from CustomParms
   └─ UtilityStepConverter deserializes each step by its "Type" field
2. Parse "GlobalParameters" dictionary
3. Validate all steps (types recognized, required fields present)
4. For each step (in order):
   a. Merge GlobalParameters, then overwrite with the step's own Parameters (step wins)
   b. Pre-resolve any {{$config:}}/{{$env:}} tokens sitting inside parameter *values*
      (IParameterResolver; JSON-escaped only for ConnEx steps)
   c. Replace tokens in the step's own fields — each token goes to ONE source chosen
      by its prefix ($config: / $env: / else parameters). No cross-source fallback;
      any unresolvable token throws and fails the step.
   d. Find matching executor
   e. Execute; collect StepExecutionResult. If it failed AND RetryEnabled → retry up to
      MaxRetries (clamped 0–10) more times, sleeping RetryDelaySeconds (clamped 0–300)
      between attempts. Retries are exhausted BEFORE ContinueOnError is evaluated.
   f. If still failed AND ContinueOnError = false → stop scenario
   g. If still failed AND ContinueOnError = true → log warning, continue
5. Scenario succeeds if all steps succeeded OR all failures had ContinueOnError = true
6. Return metrics (timing, output, exit codes per step)
```

---

## Quick-Start Example

```json
{
  "GlobalParameters": { "ServerName": "corpltr94", "DatabaseName": "TestDb" },
  "Steps": [
    {
      "Type": "CommandLineStep",
      "Description": "Check network connectivity",
      "Command": "ping",
      "Args": ["-n", "1", "{{ServerName}}"],
      "ContinueOnError": false,
      "TimeoutSeconds": 10,
      "SuccessExitCodes": [0]
    },
    {
      "Type": "SqlStep",
      "Description": "Check database connectivity",
      "SqlScript": "SELECT 1 AS ConnectionTest",
      "sqlSourceConnectionSecretName": "TestDb",
      "sqlDestinationConnectionSecretName": "TestDb",
      "UseTransaction": false,
      "CaptureScalarResult": true,
      "TimeoutSeconds": 30
    },
    {
      "Type": "PowerShellStep",
      "Description": "Check system resources",
      "ScriptContent": "Get-CimInstance Win32_OperatingSystem | Select-Object FreePhysicalMemory",
      "ContinueOnError": true,
      "TimeoutSeconds": 15
    }
  ]
}
```

---

## Key Files

| File | Purpose |
|---|---|
| `TestAuto.Shared/Constants/UtilityTypeConstants.cs` | All step type string constants |
| `TestAuto.Utilities/Common/DTOs/UtilityStepBase.cs` | Base class all steps inherit from |
| `TestAuto.Utilities/Common/DTOs/UtilityStepConverter.cs` | JSON → step object deserialization |
| `TestAuto.Utilities/Services/UtilityOrchestrator.cs` | Step execution engine |
| `TestAuto.Utilities/Executors/*.cs` | One executor class per step type |
| `TestAuto.Utilities/Samples/*.json` | Real example configurations |

## Scripts/JsonData Folder, Plugin Build, and Extending

File standards for `Scripts/JsonData`, creating and importing a `.curl` file,
token substitution in files, build/deploy notes, plugin build troubleshooting,
the checklist for adding a new step type, adding a second utilities scenario
class, and the utilities logging quirk:
**`references/authoring-and-files.md`**.

Read it when adding a step type, wiring a new utilities scenario, or working
with `.curl` / body files on disk.

---
## Sources

Full source-file list: **`references/sources.md`**.

---
## Per-Step JSON Configuration Reference

Exhaustive per-property tables and full JSON examples for every step type
(HTTP, SQL, PowerShell, CommandLine, CLU, ConnEx, Monitor):
**`references/per-step-json-reference.md`**.

Read it when you need the complete property list or a copy-paste-ready config
for one step type. The per-step sections above carry the decision rules and
gotchas; this reference carries the catalog.
