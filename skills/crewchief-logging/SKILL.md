---
name: crewchief-logging
description: >
  Serilog tag-prefix logging and case-insensitive external-JSON reads in CrewChief.Engine (re-namespaced
  copies of the TestAuto patterns). Use when adding a log call in CrewChief, choosing a LogTag, or reading
  a key off gateway/ConnEx/OAuth JSON — and to avoid citing the copied-in dead LogTag constants.
---

Repo: speed-merchants (paths below are repo-relative)

# CrewChief Logging & External-JSON Reads

CrewChief logs on **Serilog** (`Serilog.ILogger`, **not** MEL `Microsoft.Extensions.Logging.ILogger`).
`CrewChief.Engine.Logging` holds re-namespaced copies of the TestAuto tag-prefix logging helpers, and
`CrewChief.Engine.Json` holds the case-insensitive JSON accessors. Both were copied at engine-copy time
(`fb144dc7`, class/member names preserved) — so some constants came along that CrewChief never uses. See
[[crewchief-architecture]] for the copy provenance.

## When to Use
- Adding a log statement in `CrewChief.Engine` (or anything that logs with a `[TAG]`).
- Picking a `LogTagConstants` value — and confirming it's one CrewChief actually uses.
- Reading a value off external JSON (Profisee gateway, ConnEx/Connect, Matching, OAuth).
- Investigating logs and needing the `[TAG]` vocabulary that CrewChief actually emits.

## Tag-prefix logging: `LoggerTagExtensions`

Extension methods on **`Serilog.ILogger`** that **prepend `[TAG]` to the message template** so logs are
SQL-queryable even when the sink drops the `LogTag` property (`WHERE Message LIKE '%[SQL_SCRIPT]%'`).
Format: `[TAG]` or `[TAG:STAGE]` (e.g. `[SCENARIO:MetadataManagementScenario]`).

| Method | Use |
|---|---|
| `VerboseWithTag` / `DebugWithTag` / `InformationWithTag` / `WarningWithTag` / `ErrorWithTag` | level + tag prefix (each has an `Exception` overload) |
| `InformationWithTagAndConsole` / `WarningWithTagAndConsole` / `ErrorWithTagAndConsole` | also renders + writes to `Console` for startup/error visibility (swallows console failures) |
| `BeginTimedOperationWithTag(tag, description, operationId)` | `using`-block; logs "Beginning…" then "Completed … in {ElapsedMs} ms" on dispose |

`LogTagConstants.ForScenario(scenarioName)` builds the scenario tag (`SCENARIO` or
`SCENARIO:<name>`) — inherited API, used as the `tag` argument or with
`LogContext.PushProperty("LogTag", ...)`. **CrewChief itself never calls it** (see the dead-tag note
below); it survives from the TestAuto copy.

## LogTag constants — real vs. copied-cruft

`LogTagConstants` was copied wholesale from TestAuto and defines ~39 constants, but a grep of the whole
CrewChief solution shows **only 12 are referenced by production code**. Cite ONLY the real ones:

**Real (used in CrewChief production code):**

| Constant | Value | Where |
|---|---|---|
| `UtilityOrchestrator` | `UTILITY_ORCHESTRATOR` | orchestration (the workhorse tag — by far the most-used) |
| `SqlScript` | `SQL_SCRIPT` | SqlScriptExecutor |
| `Clu` | `CLU` | CLU executor/providers |
| `RestApi` | `REST_API` | HTTP client/facade |
| `PowerShellScript` | `POWERSHELL_SCRIPT` | PowerShell executor |
| `DatabaseOperations` | `DATABASE_OPERATIONS` | Database Operations step |
| `CommandLine` | `COMMAND_LINE` | CommandLine executor |
| `Connect` | `CONNECT` | ConnEx/Connect step |
| `WorkloadEngine` | `WORKLOAD_ENGINE` | WorkloadEngine |
| `ParameterResolution` | `PARAMETER_RESOLUTION` | ParameterResolver |
| `Email` | `EMAIL` | Email step |
| `Teams` | `TEAMS` | `TeamsExecutor` (`:215`, `:233`, `:241`) — the Send Teams Message step |

The newer `CheckPortStep` / `WebSiteStep` executors have **no** dedicated tag; they log under the general
executor tags. Do not invent `CHECK_PORT` / `WEBSITE` constants.

> **`Startup` (`STARTUP`) is NOT one of them — it is test-only.** Despite its `<summary>` reading
> "Startup and configuration" (`CrewChief.Engine\Logging\LogTagConstants.cs:29`), the only reference
> anywhere in the solution is the assertion at
> `CrewChief.Tests.Unit\Engine\LoggingTagTests.cs:60` — there is **no production call site**. Don't
> reach for it when adding startup/composition-root logging: nothing else in CrewChief emits
> `[STARTUP]`, so such a log would be the only one of its kind and nobody's Seq filter looks for it.
> `ScenarioPrefix` / `ForScenario` are in the same position — their only live references are
> doc-comments and `LoggingTagTests.cs`, so CrewChief emits no `[SCENARIO…]` tags either (CrewChief
> has no scenarios; that vocabulary is TestAuto's).

> **Copied-cruft — DEAD tags (defined, ZERO usage in CrewChief; do not cite):** `MetadataCrud`,
> `BatchOrchestrator` (Hangfire chaining — CrewChief has no Hangfire), `ScenarioExecution`, `Validation`,
> `LookupCache`, `RecordMix`, `WebRepository`, `WebUi`, `HttpRequest`, `Testing`,
> `ConfigurationValidation`, `TestDataEnrichment`, `TestDataCloneAndMutate`, `SecretsManagement`,
> `Metrics`, `MetadataTransformer`, `Matching`, `FileOperations`, `EnvironmentVariables`,
> `RecordsTransform`, `WorkloadExecution` (note: `WorkloadEngine` IS used, `WorkloadExecution` is NOT),
> `RecordPool`, `StepReference`, `ResourceCollection`, `RecordData`, `AttributeData`. The repo is
> read-only — this list is informational so an agent doesn't reference a tag that never appears in logs.

**Correction vs. the tasking brief:** the brief listed `Connect` ("ScenarioBaseConnect") as dead — it is
**not**; `Connect` is referenced ~10× (the ConnEx step). `BatchOrchestrator`, `WebUi`, `RecordMix`, and
`WebRepository` from the brief's example list *are* confirmed dead.

## Case-insensitive external-JSON reads

`JTokenCaseInsensitiveExtensions` (on Newtonsoft `JToken`/`JObject`) + `GatewayJsonKeys` constants.

**RULE:** never read a key off external JSON with the raw `jObject["Key"]` indexer or `SelectToken` —
they are **case-sensitive** and **silently return `null`** on a casing mismatch (the CDP platform's
contract resolvers re-case keys, so the same logical key arrives as `code`/`Code`/`CODE` by
endpoint/version — this class of bug produced empty record-create bodies and unread artifact versions).
Use instead:

- `token.GetValueCI(key)` — case-insensitive indexer equivalent.
- `token.ValueCI<T>(key)` — typed read; `default` on missing / JSON-null.
- `token.SelectTokenCI("a.b")` — case-insensitive simple dotted path (no array indexers/filters).

Pass key names as **`GatewayJsonKeys` constants**, not string literals (e.g.
`GatewayJsonKeys.ArtifactVersion`, `.Configuration`, `.Code`, `.AccessToken`). In CrewChief this backs
ConnEx `ArtifactVersion` re-injection. This is the same discipline as
[[external-json-case-insensitive-reads]]; the consuming ConnEx path is covered by
[[crewchief-step-type-model]].

## Central secret masking — `SecretMaskingEnricher` + `SecretScrubber`

Every CrewChief log event now passes through `SecretMaskingEnricher`, registered **in code** on the
`LoggerConfiguration` in **both** hosts (Web `Program.cs` and CLI `Program.cs`) rather than in
`appsettings.json` — deliberately, so an operator editing Serilog config cannot drop the masking.

`SecretScrubber` (`CrewChief.Engine/Logging/SecretScrubber.cs`) backs it with **two layers**:

1. **Known values (primary).** `Register(secret)` / `RegisterAll(...)` are called with each credential
   **after token resolution**, so the exact secret string is known and masks wherever it appears — a curl
   argument, a PowerShell command line, an error message — without the masking code understanding the
   format. This is why a password typed as a **literal**, or pulled from **reference data**, masks just as
   reliably as one drawn from the secret store: the trigger is *the field being a credential field*, not
   where the value came from. Values shorter than `MinimumRegisterableLength` (4) are ignored; the mask is
   `"***"`.
2. **Shapes (backstop).** `Scrub(text)` also applies patterns for credential syntax — `Authorization:` /
   `x-api-key:` headers, `Password=` connection-string keywords — covering a value that reached a log
   before it was ever registered.

> [!warning] Two things the enricher cannot reach
> **Message-template literals** and **attached `Exception` text**. Serilog renders `LogEvent.Exception`
> separately from the properties an enricher can rewrite, so a secret inside third-party error text
> survives. Any site logging third-party error text must pass it through `SecretScrubber.Scrub` explicitly
> and log the **result as a property** — the `RemoteWinRmProber` / `ShareFirstHopProber` helpers already do
> the equivalent.

**User ids are deliberately NOT masked** — they are needed to diagnose an auth failure and are not the
secret. Only passwords, passphrases and API keys mask.

Testing note: the known-value registry is **process-global** (it sits behind the process-singleton Serilog
logger), so `SecretScrubberTests` calls `ResetKnownValuesForTests()` in both `[TestInitialize]` and
`[TestCleanup]` and carries `[DoNotParallelize]` — see [[crewchief-testing]].

## Related
- [[dotnet-logging-schema]] · [[testauto-log-tags]] · [[external-json-case-insensitive-reads]] · [[crewchief-architecture]]
- Migration context: memory [[project_logging_migration]]

## Sources
- `CrewChief\CrewChief.Engine\Logging\LoggerTagExtensions.cs`
- `CrewChief\CrewChief.Engine\Logging\LogTagConstants.cs`
- `CrewChief\CrewChief.Engine\Json\JTokenCaseInsensitiveExtensions.cs`
- `CrewChief\CrewChief.Engine\Json\GatewayJsonKeys.cs`
- Usage counts verified by grepping `LogTagConstants.<name>` across `CrewChief\` (excluding the definition file).
