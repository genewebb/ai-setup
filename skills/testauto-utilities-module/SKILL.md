---
name: testauto-utilities-module
description: >
  Maintainer guide for the TestAuto.Utilities plugin module — MultiStepUtilityScenario, the eight
  IStepExecutor implementations, UtilitiesModuleRegistrar DI, and the build/deploy pipeline. Use when
  CHANGING or EXTENDING the module: adding a step type + executor, editing the registrar, debugging
  the CopyToHosts staleness gotcha or the duplicate CURL registration, TextTemplater or
  IParameterResolver internals, UtilityStepTypeInfo metadata, redacting resolved ConnEx credentials
  before they reach a log (ConnExArtifactMasker), or truncating step output before it is written to
  metrics and logs. For WRITING step JSON see [[testauto-multistep-steps]].
---

Repo: speed-merchants (paths below are repo-relative)

# TestAuto.Utilities — Module Maintainer Guide

Guidance for **changing or extending** the `TestAuto.Utilities` module: multi-step
automation (SQL, PowerShell, command line, CLU, HTTP) driven by scenario configuration.
This is the *maintainer/extender* view of the module. The *consumer/config-author* view
(how to write the JSON, every step type's fields, token syntax) lives in
[[testauto-multistep-steps]]; the polymorphic step deserialization lives in
[[utility-step-polymorphic-deserialization]].

> **Origin**: migrated from the repo-local `TestAuto.Utilities/Agents.md`.

## When to Use

- "How do I add a new step type to the Utilities module?"
- "Why didn't my Utilities change take effect when I ran a scenario?" (plugin staleness)
- "Which executor actually handles CURL/HTTP steps?"
- "Where do I register a new IStepExecutor?"
- "Why did ScriptKey/ScriptLocator file resolution go away — where does step content live now?"

## What this project is

- **Role**: Plugin assembly (`TestAuto.Utilities.dll`) loaded by hosts (**TestAuto.Web**,
  **TestAuto** console, **TestAuto.Testing**). Supplies the **`MultiStepUtilityScenario`**
  implementation and all step execution infrastructure.
- **Primary scenario**: `MultiStepUtilityScenario` (`Scenarios/MultiStepUtilityScenario.cs`)
  — `ScenarioName` = **`MultiStepUtilityScenario`**. Custom UI:
  **`CustomParmsEditorType.UtilityScenarioEditor`** (Blazor `UtilityScenarioEditor`).
- **Execution model**: Config supplies **`CustomParms.Steps`** (ordered list) and optional
  **`CustomParms.GlobalParameters`**. `UtilityOrchestrator` runs steps **sequentially**;
  failures stop the run unless the step sets **`continueOnError: true`**.

## Layout (folders agents touch most)

| Area | Path | Purpose |
|------|------|--------|
| Scenario entry | `Scenarios/` | `MultiStepUtilityScenario` (today: single scenario class) |
| Step DTOs | `Common/DTOs/` | `UtilityStepBase`, `SqlStep`, `PowerShellStep`, `CommandLineStep`, `CLUStep`, `HttpRequestStep`, `ConnExStep`, `MonitorStep`, `UtilityStepConverter` |
| Executors | `Executors/` | `IStepExecutor` implementations (one canonical `StepType` string each) |
| Orchestration | `Services/` | `UtilityOrchestrator`, `TextTemplater`, `ParameterResolver` (`ScriptLocator` retired) |
| Helpers | `Helpers/` | `ScriptDiscoveryService`, `TextTruncationHelper`, `ConnExArtifactMasker`, `ConnExErrorParser` |
| DI | `AutoRegistration/UtilitiesModuleRegistrar.cs` | Registers utilities services and **all** `IStepExecutor` implementations |
| Scripts | `Scripts/**` | Bundled SQL/PowerShell tree, shipped to output. **No longer a runtime step-content source** (steps are inline); used by the config-migration recovery — see "Scripts and the script root" |
| Samples | `Samples/*.json` | Example payloads (documentation / copy-paste); not auto-executed |
| Tests | `../TestAuto.Utilities.Tests/` | Integration tests; must use **`RegisterAllServices`** like production |

## Configuration contract (`CustomParms`)

Parsed in **`UtilityBase.ApplyConfiguration`** → **`ParseStepsFromConfiguration`** /
**`ParseGlobalParameters`**. Required shape under `ScenarioRuntime.CustomParms`:

- **`Steps`**: JSON array of step objects. Each **must** include **`Type`** / **`type`**
  (case-insensitive) matching a known step kind.
- **`GlobalParameters`**: Optional dictionary of string key-values. Merged into each step's
  parameters for **`{{Token}}`** substitution; **step parameters override** globals on conflict.

## Step types (JSON `Type` → runtime)

| JSON `Type` (examples) | DTO | Executor `StepType` | Implementation |
|------------------------|-----|---------------------|----------------|
| `SqlStep`, `SQL` | `SqlStep` | `SqlStep` | `SqlScriptExecutor` |
| `PowerShellStep`, `PowerShell`, `PS` | `PowerShellStep` | `PowerShellStep` | `PowerShellScriptExecutor` |
| `CommandLineStep`, `CommandLine`, `CLI`, `CMD` | `CommandLineStep` | `CommandLineStep` | `CommandLineExecutor` |
| `CLUStep`, `CLU` | `CLUStep` | `CLU` | `CLUExecutor` |
| `HttpRequestStep`, `HTTP`, `CURL`, `CurlStep`, … | `HttpRequestStep` | **`CURL`** | **`PowerShellRestExecutor`** (registered **after** `CurlExecutor`) |
| `ConnExStep`, `ConnEx` | `ConnExStep` | `ConnExStep` | `ConnExExecutor` |
| `MonitorStep`, `Monitor` | `MonitorStep` | `MonitorStep` (via `UtilityTypeConstants.MonitorStep`) | `MonitorStepExecutor` |

**Eight** `IStepExecutor` implementations are registered, in this order (`UtilitiesModuleRegistrar.cs:46-53`): `SqlScriptExecutor`, `PowerShellScriptExecutor`, `CommandLineExecutor`, `CLUExecutor`, `CurlExecutor`, `PowerShellRestExecutor`, `ConnExExecutor`, `MonitorStepExecutor`. That is **eight registrations but only seven reachable step types**, because `CurlExecutor` and `PowerShellRestExecutor` both claim `StepType => "CURL"` (see the quirk below).

Orchestrator aliases are registered in the `UtilityOrchestrator` constructor (`UtilityOrchestrator.cs:62-73`) and include `ConnEx → ConnExStep` and `Monitor → MonitorStep`. `AddExecutorAlias` is a **no-op when the alias key already exists**, so an alias can never displace a real `StepType`.

- **Deserialization**: **`UtilityStepConverter`** and **`UtilityStepBase.CreateFromJToken`**
  must agree on the same type names. If you add aliases, update **both** places.
- **Orchestrator aliases**: `UtilityOrchestrator` maps alternate names (e.g. `SQL` →
  `SqlStep`, `HTTP` → `CURL`) via its constructor.

> **⚠️ Duplicate `StepType` registration quirk**: Both `CurlExecutor` and
> `PowerShellRestExecutor` expose `StepType => "CURL"`. DI registers **`CurlExecutor` then
> `PowerShellRestExecutor`**; the orchestrator's dictionary keeps the **last** registration,
> so **`PowerShellRestExecutor` handles `CURL`/HTTP steps**. It uses
> `HttpRequestStep.UseRestMethod` (default `true`) to choose Invoke-RestMethod vs curl-style
> execution. Do not add another `IStepExecutor` with the same `StepType` without reconciling this.

## Token and templating (`TextTemplater`)

- **`{{Key}}`**: merged global + step parameters (case-insensitive keys).
- **`{{$config:Section:Key}}`**: from **`IConfiguration`** (TextTemplater must be constructed
  with configuration — `UtilitiesModuleRegistrar` does this).
- **`{{$env:VAR}}`**: environment variables.
- Unresolved tokens cause **fail-fast** `ArgumentException` at replacement time.

(Full token reference for config authors: [[testauto-multistep-steps]].)

### `ITextTemplater` API surface (`Services/TextTemplater.cs`)

- **`string ReplaceTokens(string input, IDictionary<string, string> parameters)`** — validates first,
  then replaces; throws `ArgumentException` listing **every** unresolvable token (the fail-fast above).
- **`ISet<string> FindTokens(string input)`** — unique token *names* found in the input, **without**
  the `{{}}` braces, in a case-insensitive `HashSet`; empty set for null/empty input.
- **`IEnumerable<string> ValidateTokens(string input, IDictionary<string, string> parameters)`** —
  names of tokens that **cannot** be resolved from any source (empty result = safe to `ReplaceTokens`).
  Quirk: `$config:`/`$env:` tokens must resolve to a **non-empty** value to count as resolvable;
  plain parameter tokens only need the **key to exist** (null/empty values are fine).
- Parameter keys are **case-insensitive** throughout (inputs are wrapped in `OrdinalIgnoreCase`
  dictionaries internally).
- Two constructors: `TextTemplater(IConfiguration)` enables `$config:` (the registrar uses this);
  parameterless = parameter/`$env:` tokens only (`$config:` tokens then always validate as missing).

### Pre-resolving special tokens in parameter *values* (`IParameterResolver`)

`{{$config:...}}` / `{{$env:...}}` can appear not just in script bodies but in a **parameter value**
itself. This pre-resolution was extracted from the orchestrator into a shared service:
**`Interfaces/IParameterResolver.cs`** + **`Services/ParameterResolver.cs`** (wraps `ITextTemplater`).
Two methods:

- **`void ResolveSpecialParameterValues(IDictionary<string, string> parameters, bool escapeForJson = false)`** —
  in-place pre-pass: any value containing `{{$config:` or `{{$env:` (case-insensitive) is resolved via the
  templater with an `EmptyParameters` sentinel (so only special tokens — not artifact `{{Token}}`s — resolve in
  that pass). All-or-nothing per value: if `ValidateTokens` reports anything unresolvable, the **whole value is
  left intact** with a warning so the step executor's own validation surfaces the missing source. When
  `escapeForJson: true` each resolved value is JSON-string-literal escaped (`EscapeForJsonStringLiteral`, doubles
  `\` / escapes `"`) — set only for ConnEx steps, which substitute params into a raw JSON artifact. Literal
  params carry no `{{$config}}`/`{{$env}}` token so they are skipped → never double-escaped. See
  [[connex-import-tokenization]] for the full escaping rationale.
- **`string ResolveBestEffort(string input, IDictionary<string, string> parameters)`** — resolves every
  token it *can* (case-insensitive parameter copy plus `$config:`/`$env:`), token-by-token, leaving
  unresolvable ones in place. **Never throws** — intended for display strings (e.g. scenario names).

**Consumers (same logic, two points in time):**

- **Run time** — `UtilityOrchestrator` calls `ResolveSpecialParameterValues(mergedParams, escapeForJson: step is ConnExStep)`
  per step before executor token replacement (ConnEx params are substituted into a raw JSON artifact, so their
  resolved values must be JSON-escaped; SQL/PowerShell/Curl/CLU consume raw values and pass `false`). ⚠️ The
  orchestrator does **not** take `IParameterResolver` from DI — it constructs
  `new ParameterResolver(_textTemplater, _logger)` internally so its public constructor stays unchanged.
- **Import time** — `TestAuto.Web/Services/ConnExScenarioFactory` injects `IParameterResolver`:
  `ResolveSpecialParameterValues` over the import's global parameters, then `ResolveBestEffort` to build
  the stored scenario display name/description.

**DI**: `services.AddTransient<IParameterResolver, ParameterResolver>();` in `UtilitiesModuleRegistrar`.

**Why it exists:** ConnEx imports create a two-hop chain — an artifact token like `{{DbUsername}}` maps to a
parameter whose *value* is `{{$config:Passwords:...}}`. Without this pre-pass, the literal `{{$config:...}}`
would survive into the executed payload. Add value-level special-token support in **`ParameterResolver`**
(not in `TextTemplater`, not per-executor) when a new code path needs the same two-hop behavior.

## Scripts and the script root (`ScriptKey`/`ScriptLocator` retired)

> **Runtime script-file resolution has been retired.** `IScriptLocator` / `ScriptLocator` are **deleted**, and steps no longer reference content by `ScriptKey` / `BodyFilePath` — all step content is **inline** (`sqlScript` / `scriptContent` / `body` / `command`; see [[testauto-multistep-steps]]). There is no `{ScriptsRoot}\{ScriptKey}` lookup at execution time anymore.

What remains:

- **`ScriptDirectoryOptions`** (`TestAuto.Shared/Configuration/ScriptDirectoryOptions.cs`) still exists: `FromConfiguration(configuration)` reads the single **`DirectoryPaths:ScriptDirectory`** secret-backed root, and **`ResolveRelativePath(path)`** is the shared helper (relative paths resolve under the root; absolute paths pass through). It is used by `ScriptDiscoveryService` and, notably, by the **one-time conversion job** that recovers and inlines legacy `bodyFilePath` content under the script root — see [[testauto-config-store-migration]].
- `TestAuto.Utilities.csproj` still copies a bundled **`Scripts\**\*`** tree to output/publish (e.g. `Scripts/SQL/Utility/CreateDatabase.sql`). This folder is no longer a runtime step-content source — it ships so the conversion job's recovery can find and inline legacy file bodies on any machine.
- Authoring a step today: put the SQL/PowerShell/body/command **inline** in the step JSON. Do not add a `ScriptKey`/`BodyFilePath` — there is no runtime fallback to a file.

## Adding a new step **type** (checklist)

1. **DTO**: Add `XxxStep : UtilityStepBase` in `Common/DTOs/` with `[JsonProperty]` names matching JSON (typically camelCase).
2. **Converter**: Extend **`UtilityStepConverter.ReadJson`** switch **and**
   **`UtilityStepBase.CreateFromJToken`** — keep them aligned.
3. **Executor**: Implement `IStepExecutor` with a **unique** `StepType` string (PascalCase matching the JSON primary name is conventional).
4. **DI**: `services.AddTransient<IStepExecutor, XxxExecutor>();` in **`UtilitiesModuleRegistrar`**.
5. **Aliases** (optional): `UtilityOrchestrator.AddExecutorAlias(...)` for alternate JSON type names.
6. **Metrics** (if needed): extend **`MultiStepUtilityScenario.ProcessBatchAsync`** like the `CLUStep` / `HttpRequestStep` branches.
7. **Sample**: add an example under **`Samples/`**.
8. **Tests**: extend **`TestAuto.Utilities.Tests`** (integration tests use full DI — see `Integration/ScenarioIntegrationTests.cs`).
9. **UI picker metadata** (Web-side): add a case for the new type to **`UtilityStepTypeInfo`** so the Add-Step picker shows a real icon/name/description/colors instead of the generic fallback — see below.

### Add-Step picker visual metadata — `UtilityStepTypeInfo` (TestAuto.Web)

`TestAuto.Web/Helpers/UtilityStepTypeInfo.cs` is a `static` class — the single source of truth for a step
type's **visual** metadata in the UI (this is presentation only; nothing here affects execution). Five
`type.ToUpperInvariant() switch` lookups, all keyed by the codes from `IReferenceDataCache.GetUtilityTypes()`:

| Method | Returns | Example (`SQL`) |
|---|---|---|
| `GetIcon(type)` | Material Symbols icon name (see [[blazor-icons]]) | `storage` |
| `GetDisplayName(type)` | Friendly title | `SQL Script` |
| `GetDescription(type)` | One-line "what it does" | `Execute SQL scripts with source and destination connections` |
| `GetAccentColor(type)` | Foreground/border hex | `#0d6efd` |
| `GetBgColor(type)` | Tint/background hex | `#e7f0ff` |

- **Consumer**: only `UtilityScenarioEditor` (`.razor` markup calls `UtilityStepTypeInfo.*` directly; the
  `.razor.cs` is the same partial class). It backs both the Add-Step picker cards and the inline type-selector row.
- **Aliases**: each `switch` arm folds the JSON aliases together — `COMMANDLINE`/`CLI`/`CMD`,
  `HTTP`/`HTTPREQUEST`, `CONNEX`/`CONNEXSTEP`, `MONITOR`/`MONITORSTEP` — mirror the same alias set you add in
  step 5 above so every alias renders identically.
- **Fallback**: an unmatched type is not an error — it silently falls back (`play_circle` icon, the raw type
  string as the name, generic description, grey `#6c757d`/`#f8f9fa`). So a new step type "works" in the picker
  but looks generic until you add its five cases. This is the whole reason this is a checklist step, not optional.

## Changing existing step behavior

- **Executor-only change** (same JSON contract): edit the executor under `Executors/`;
  honor `IStepExecutor` semantics (return `StepExecutionResult`, honor `CancellationToken`,
  respect `ContinueOnError` at the orchestration layer).
- **DTO / JSON contract change**: treat as **breaking** for saved scenarios. Prefer additive
  optional properties. Update samples and the `UtilityScenarioEditor` Blazor editor if it binds those properties.
- **SQL access**: use solution patterns (e.g. **`SqlHelper`**); `SqlScriptExecutor` is the central place for SQL step behavior.

## Web UI and scenario type metadata

- **`[ScenarioTypes(..., CustomParmsEditorType.UtilityScenarioEditor)]`** on
  `MultiStepUtilityScenario` selects the structured editor.
- Related Web files: **`TestAuto.Web/Components/Controls/UtilityScenarioEditor.razor.cs`**,
  scenario testing pages (`ScenarioUtilityTesting.razor.cs`).
- Adding a **second** utilities scenario class requires: new `IScenario` impl, correct
  **`ScenarioTypesAttribute`** (see [[testauto-scenario-types-attribute]]), plugin discovery
  unchanged (same assembly), Web editor routing if a new editor type is introduced, and validation registration if applicable.

## Build and deployment of the plugin

- After **build**, **`CopyToHosts`** copies `TestAuto.Utilities.dll` (+ pdb) to
  **`TestAuto/Plugins`**, **`TestAuto.Web/Plugins`**, **`TestAuto.Testing/Plugins`**.
- You must **build TestAuto.Utilities** (or the solution) so hosts pick up changes — a
  **stale `Plugins` folder is the most common "why didn't my change run?" cause**.

## ConnEx credential masking before logging (`ConnExArtifactMasker`)

`ConnExExecutor` logs the import artifact body for diagnostics — but after token resolution that JSON
holds **real** secrets (DB username/password) at the reshaped LocalVault path `value.configuration.value`.
Before logging, pass the artifact through **`ConnExArtifactMasker.MaskCredentials(artifactJson)`**
(`Helpers/ConnExArtifactMasker.cs`):

- Recursively walks the JSON; for every node with `assignmentType: "Credential"` it replaces the secret at
  `value.configuration.value` (or, defensively, a string `value`) with `ConnExArtifactMasker.RedactedMarker`
  (`***REDACTED***`).
- Returns the input **unchanged** if it's null/empty or not parseable as JSON (safe to wrap any log payload).
- **Only the log copy is masked** — the real artifact (with secrets) is still sent to ConnEx.

Rule of thumb: never log a resolved ConnEx artifact directly; always log `MaskCredentials(...)` of it. Reuse
this helper for any new code path that logs credential-bearing artifact JSON.

## Output truncation before metrics/logging

**Six of the eight executors** (SqlScript, PowerShellScript, PowerShellRest, Curl, CommandLine,
CLU) bound captured input/stdout/stderr with their **own private
`TruncateForMetrics(text, maxLength)`** method before writing it to `StepExecutionResult`
fields (e.g. `SqlScriptExecutor.cs:542`, `CurlExecutor.cs:389`). `InputText` is truncated
at 4000; output/error limits vary per executor (4000 for PowerShellRest/Curl, 8000 for CLU
stdout, 10000 for PowerShellScript/CommandLine). **Any new executor or metric field must
do the same — never store raw output**, or large outputs blow past Profisee's 4000-char
attribute ceiling (error 8610).

The other two — **`ConnExExecutor` and `MonitorStepExecutor` — have no `TruncateForMetrics`**.
`MonitorStepExecutor` captures no external process output. `ConnExExecutor` bounds its response
body a different way, via the shared constant `ConnExConstants.ResponseSnippetMaxLength` (2,048)
into `ConnExStepDetail.ResponseSnippet`/`ResponseTotalLength` — see [[testauto-multistep-steps]].
So "add a private `TruncateForMetrics`" is the rule for **process-output** executors; an
HTTP-response executor should follow the ConnEx snippet pattern instead.

A shared **`TextTruncationHelper`** (`Helpers/TextTruncationHelper.cs`) also exists, but
it has **zero production call sites** — it is exercised only by its unit tests
(`Testing.SpeedMerchants.Unit\Tests\Utilities\Helpers\TextTruncationHelperTests.cs`); the
executors do not use it. Its ladder, should you consolidate onto it:

| Method | Limit | Use for |
|---|---|---|
| `TruncateForMetrics(s)` | 4000 | Metric detail attribute values (the Profisee attribute ceiling) |
| `TruncateForLogging(s)` | 1000 | Serilog log lines |
| `TruncateForDisplay(s)` | 500 | UI-facing strings |
| `TruncateWithMarker(s, n)` | custom (`n >= MinimumMaxChars = 100`, else `ArgumentException`) | Anything else |
| `CombineAndTruncate(lines, n, sep)` | custom | Joining stdout + stderr streams before bounding |

The helper's truncation is **head-and-tail preserving**: the split slightly favors the head
and inserts ` ... [N chars truncated] ... ` in the middle, so both the start of the output
and the final error lines survive. `WouldBeTruncated(s, n)` is available for pre-checks.
(The executors' private methods are simple head-truncate-with-marker, not head-and-tail.)

## Logging (current quirk)

Much of the utilities pipeline logs with **`LogTagConstants.SqlScript`** (including the
orchestrator and several executors), not a dedicated "Utilities" tag. Follow existing
Serilog + `LogTagConstants` patterns (see [[testauto-log-tags]]); avoid repeated string literals.

## Dependencies

- **Project references**: `TestAuto.Scenarios`, `TestAuto.Shared`, `TestAuto.Metrics`.
- No circular references. Shared scenario/config types live in **TestAuto.Shared**; batch hosting in **TestAuto.Scenarios**.

## Quick reference — key files

| Concern | File |
|--------|------|
| Scenario | `Scenarios/MultiStepUtilityScenario.cs` |
| Config parsing | `Common/UtilityBase.cs` |
| Step JSON polymorphism | `Common/DTOs/UtilityStepConverter.cs`, `UtilityStepBase.cs` |
| Run loop | `Services/UtilityOrchestrator.cs` |
| Tokens / templating | `Services/TextTemplater.cs` |
| `$config:`/`$env:` value pre-resolution | `Interfaces/IParameterResolver.cs`, `Services/ParameterResolver.cs` |
| Script root (file resolution retired) | `TestAuto.Shared/Configuration/ScriptDirectoryOptions.cs` (`ScriptLocator` deleted) |
| DI | `AutoRegistration/UtilitiesModuleRegistrar.cs` |
| HTTP/CURL steps | `Common/DTOs/HttpRequestStep.cs`, `Executors/PowerShellRestExecutor.cs`, `Executors/CurlExecutor.cs` |

## When to update this skill

Update when you: add/rename a step type, executor, or JSON property; change `CustomParms`
shape, token syntax, or orchestration semantics; change plugin copy targets or project
references; or add a new first-class utilities scenario beside `MultiStepUtilityScenario`.

## Sources

- `TestAuto.Utilities\Agents.md` (original repo-local guide) — *source removed 2026-07-27; content migrated to work-ai, this skill is now canonical*
- `TestAuto.Utilities\Scenarios\MultiStepUtilityScenario.cs`
- `TestAuto.Utilities\Common\UtilityBase.cs`
- `TestAuto.Utilities\Common\DTOs\UtilityStepConverter.cs`
- `TestAuto.Utilities\Services\UtilityOrchestrator.cs`
- `TestAuto.Utilities\Interfaces\IParameterResolver.cs`, `Services\ParameterResolver.cs` (shared `$config:`/`$env:` value pre-resolution)
- `TestAuto.Utilities\Services\TextTemplater.cs` (`ReplaceTokens` / `FindTokens` / `ValidateTokens`)
- `TestAuto.Utilities\Services\ScriptLocator.cs` — *deleted in the file-reference retirement; runtime ScriptKey resolution removed (steps are inline-only)*
- `TestAuto.Shared\Configuration\ScriptDirectoryOptions.cs` (`DirectoryPaths:ScriptDirectory` root, `FromConfiguration`, `ResolveRelativePath` — still used by config migration / `ScriptDiscoveryService`)
- `TestAuto.Web\Services\ConnExScenarioFactory.cs` (import-time `IParameterResolver` consumer)
- `TestAuto.Utilities\AutoRegistration\UtilitiesModuleRegistrar.cs`
- `TestAuto.Utilities\Helpers\TextTruncationHelper.cs` (truncation ladder; unit-test-only — executors use their own private `TruncateForMetrics`)
- `TestAuto.Utilities\Executors\PowerShellRestExecutor.cs`, `CurlExecutor.cs`
- `TestAuto.Utilities\Executors\ConnExExecutor.cs`, `Helpers\ConnExArtifactMasker.cs` (credential masking before logging)
- `TestAuto.Utilities\TestAuto.Utilities.csproj`
- `TestAuto.Web\Helpers\UtilityStepTypeInfo.cs` (Add-Step picker visual metadata: icon/name/description/accent+bg color per step type; keyed by `IReferenceDataCache.GetUtilityTypes()`)
- `TestAuto.Web\Components\Controls\UtilityScenarioEditor.razor(.cs)` (sole consumer of `UtilityStepTypeInfo`)
