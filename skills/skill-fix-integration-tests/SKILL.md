---
name: skill-fix-integration-tests
description: >
  Playbook for driving the speed-merchants test suites (Unit OR Integration) to green. Lists existing
  .trx runs, prompts for one, then branches: Unit → categorize and fix only; Integration → full loop
  with env prereqs, LIVE Profisee/SQL/WebUI dependencies, and the atomic-test rules. Use when tests
  are failing, when asked to "fix the tests" or "get the suite green", when triaging a batch of
  failures, or when one category needs fixing.
---

Repo: speed-merchants (paths below are repo-relative)

# Fix the speed-merchants Test Suites

> **Project**: `{SpeedMerchantsRepo}`
> **Targets**: `Testing.SpeedMerchants.Unit` (in-process, fast) OR `Testing.SpeedMerchants.Integration` (LIVE
> — hits Profisee gateway, ScenarioMgt, SQL, and for some tests the running TestAuto.Web app).
> **Results folder**: `TestResults\` (timestamped TRX files live here).

---

## Step 0 — Pick the TRX to analyze (REQUIRED)

The bundled helper ships beside this `SKILL.md`. Resolve it from wherever this skill is installed —
under Claude Code that's `$env:USERPROFILE\.claude\skills\skill-fix-integration-tests\select-trx.ps1`
(Copilot: `…\.copilot\skills\…`). **Never hard-code one client's path blindly.** The variable below is the
script path you resolved:

> **Read-Host hangs the agent.** Your shell is `-NonInteractive`, so the bare interactive form of the script
> will hang/abort. Use the **two-call flow**: `-List` to see the runs, then `-Choice N` once the user picks.

**Call 1 — list (agent-safe, never prompts):**

```powershell
$picker = "$env:USERPROFILE\.claude\skills\skill-fix-integration-tests\select-trx.ps1"
pwsh -NoProfile -File $picker -List
```

It enumerates `*.trx` in `TestResults\` (newest first), prints a numbered
table (`#`, File, Suite, Age, Size, Passed/Failed/Skipped), and emits machine-readable
`CANDIDATE:#=…;Suite=…;Failed=…;Path=…` lines, then exits 0 **without prompting**.

Present the candidates to the user and ask which number to analyze.

**Call 2 — select (after the user answers):**

```powershell
pwsh -NoProfile -File $picker -Choice 2
```

This emits `SELECTED:Path=…`, `SELECTED:Suite=…`, `SELECTED:Failed=…` lines you parse, **plus**
`CLUSTER:Count=N;[Class] first-line-of-message` lines (largest shared root cause first) so you can start
the loop immediately without a second parsing pass.

> **Suite label caveat:** `Suite` is inferred from the test-class namespaces (then filename). A run spanning
> both projects is labeled `Mixed` — treat it as Integration for env purposes, or re-run one project at a time.

If `TestResults\` is missing or empty, run a baseline first (see **Baseline commands** below) and re-run
the helper.

### One clarifying question after selection

Ask the user **one** thing: *target category filter or whole suite?* Then use that as the `--filter`
predicate in every re-run. Examples:

- Whole suite (no filter)
- `FullyQualifiedName~Web.Integration`
- `FullyQualifiedName~Tests.Matching`
- `FullyQualifiedName~Utilities.Integration`
- `FullyQualifiedName~RESTGateway.Entity`

Available category namespaces: `Web.Integration`, `Tests.Matching`, `Utilities.Integration`,
`RESTGateway.Entity`, `RESTGateway.Connect`, `RESTGateway.Client`, `DataRecordGenerators`, `Cache`,
`CommandLine`, `Configuration`, `Security`, `Workflows`.

---

## Step 1 — Branch on suite

| Suite           | What applies                                                                                  |
| --------------- | --------------------------------------------------------------------------------------------- |
| **Unit**        | Loop + Mechanics + Atomicity + Root-cause table. **Skip** Env prereqs (no Profisee/SQL/WebUI).|
| **Integration** | Everything below applies, including Env prereqs and Skip criteria.                            |
| **Mixed**       | TRX spans both projects. Treat as Integration (env prereqs apply); prefer re-running one project at a time. |
| **Unknown**     | Ask the user which suite the TRX came from before proceeding.                                 |

---

## The loop — plan → fix → test, one category at a time

Work the **largest failing category first**, then the next, etc. Never try to fix everything at once.

1. If an image is pasted, use it as the starting list + counts. Otherwise use the TRX picked in Step 0 (or
   re-baseline).
2. **Baseline** — run the whole suite (or the target category) with a TRX logger. Record the count.
3. **Categorize** — parse the TRX, cluster failures by `class :: first-line-of-message`. The cluster with the
   most members usually shares ONE root cause.
4. **Diagnose the shared root cause** of the top cluster: read the full error + stack, read the test, read
   the production code it calls. Find the *one* fix that clears the whole cluster.
5. **Fix** it (prefer fixing the shared root over per-test band-aids). Keep every fix **atomic** — see the
   Atomicity section.
6. **Re-run that category only** (`--no-build` after a build) and re-baseline.
7. **Repeat** for the next cluster / next category.
8. **Skip and move on** for failures you genuinely can't fix in-repo (see *Skip criteria*); note them, don't
   churn.

---

## Mechanics — commands that make the loop fast

### Pre-flight: kill stale test hosts (Integration only)

A lingering `testhost` locks `TestAuto.Web.dll` and the build fails with MSB3027 *"being used by another
process"*. Do **NOT** kill the running WebUI app (a `dotnet` process serving 8443) — only `testhost` /
`vstest.console`:

```powershell
Get-Process testhost,vstest.console -ErrorAction SilentlyContinue |
  ForEach-Object { try { $_.Kill() } catch {} }
Start-Sleep 2
```

### Baseline commands — write TRX into TestResults\ with a timestamp

Build once, then `--no-build` for every subsequent run (saves ~90s per iteration). Run from the repo root.

```powershell
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$results = 'TestResults'

# Unit suite
dotnet build Testing.SpeedMerchants.Unit\Testing.SpeedMerchants.Unit.csproj -v quiet --nologo
dotnet test  Testing.SpeedMerchants.Unit\Testing.SpeedMerchants.Unit.csproj --no-build `
  --logger "trx;LogFileName=unit-$stamp.trx" --results-directory $results

# Integration suite (with a category filter)
dotnet build Testing.SpeedMerchants.Integration\Testing.SpeedMerchants.Integration.csproj -v quiet --nologo
dotnet test  Testing.SpeedMerchants.Integration\Testing.SpeedMerchants.Integration.csproj --no-build `
  --filter "FullyQualifiedName~Web.Integration" `
  --logger "trx;LogFileName=integration-web-$stamp.trx" --results-directory $results
```

### Cluster the failures from a TRX

`select-trx.ps1 -Choice N` already emits `CLUSTER:` lines for the picked TRX — use those first. Re-cluster
manually with the snippet below only for a **freshly produced** TRX from a category re-run (Step 6), pointing
it at that new file (or the `SELECTED:Path` value):

```powershell
$trx = 'TestResults\<your-file>.trx'
[xml]$t = Get-Content $trx
$ns = 'http://microsoft.com/schemas/VisualStudio/TeamTest/2010'
$nm = New-Object System.Xml.XmlNamespaceManager((New-Object System.Xml.NameTable))
$nm.AddNamespace('t', $ns)
$d = @{}
foreach ($u in $t.SelectNodes('//t:UnitTest', $nm)) { $d[$u.id] = $u.TestMethod.className }
$t.SelectNodes('//t:UnitTestResult[@outcome="Failed"]', $nm) | ForEach-Object {
  $c   = (($d[$_.testId] -split ',')[0] -split '\.')[-1]
  $msg = $_.Output.ErrorInfo.Message
  $line = if ($msg) { ($msg -split [char]10)[0].Trim() } else { '' }
  '[' + $c + '] ' + $line.Substring(0, [Math]::Min(110, $line.Length))
} | Group-Object | Sort-Object Count -Descending | Format-Table Count, Name -AutoSize -Wrap
```

To drill into one failure, select by `testName` and print `Output.ErrorInfo.Message` (first lines) +
`StackTrace` (first 3 lines), and `Output.StdOut` (the test's `Console.WriteLine` diagnostics — often the
gateway response or SQL error that explains the failure).

> A full Integration-suite run is ~15-20 min (the Matching perf/load tests dominate). Run it in the
> background and categorize from the TRX when it lands; iterate on single categories in the foreground.

---

## Environment prerequisites — INTEGRATION ONLY (check FIRST; many "failures" are env, not code)

- **Secrets file** must be loaded. The suite reads a TestAutoSecrets export whose path is the config item
  `IntegrationTests:SecretsFilePath` (in `appsettings.integration.json`, env-overridable via
  `IntegrationTests__SecretsFilePath`). It's flattened+`{{Section:Key}}`-resolved with the production
  `TestAuto.Shared.Security.Services.SecretSchema` (`ResolveInternalReferences` + `FlattenForConfiguration`)
  and spliced in as an in-memory config source in `BaseTest.Setup` BEFORE `RegisterAllServices`. Symptom when
  missing: `"Profisee RestClients entry must define both BaseUrl and ApiKey"`.
- **TrustServerCertificate** — Microsoft.Data.SqlClient defaults to `Encrypt=True`; local SQL uses a
  self-signed cert. The loader appends `;TrustServerCertificate=True` to every `ConnectionStrings:*` value
  missing it. Symptom: `"certificate chain ... not trusted"`. Hard-coded in-test connection strings need it too.
- **The running WebUI app** — tests using `IWebUiClient` or hitting `/api/...` need TestAuto.Web running.
  The Release publish listens on **8443** (https), not 7019. Point the client there via
  `appsettings.integration.json` → `WebUI:HttpsPort: 8443`. Symptom: `IWebUiClient` calls return null / can't
  connect. Don't restart the app the user started.
- **Standalone Setups** that build their own `ServiceCollection` + `ConfigurationBuilder` instead of inheriting
  `BaseTest` usually miss secrets and/or `IWebUiClient` registration — route them through `BaseTest` (call
  `base.Setup()`, resolve from `ServiceProvider`).

---

## Atomicity is mandatory (every fix must keep it)

A test must run in isolation, in any order, in parallel, repeatably, leaving no state behind. (See the
`atomic-tests` skill / `feedback-tests-must-be-atomic` memory.) Concretely:

- **Self-provision** what the test needs (entity record / matching strategy / scenario / template / ConnEx
  config) and **delete it in cleanup**. Never depend on a pre-existing instance record or a literal id
  (e.g. `TMP_12345`, `RetailClient` strategy) — that's flaky and fails domain validation when absent.
- **Survive partial Setup failure**: MSTest skips `[TestCleanup]` if `[TestInitialize]` throws — so Setup must
  `try { provision } catch { teardown; throw; }`, and `[TestCleanup]` calls the same teardown.
- **Unique keys per run** (`$"LT_{runId}_{i}"`, `RtMatchTest_{guid}`) so bulk writes don't collide with prior
  runs / source data; pre-delete by unique key for idempotency.
- **`[DoNotParallelize]`** any class that mutates the shared model (creates/deletes entities, calls
  `ReloadCache`) OR runs a migration that touches ALL instance data — otherwise it races readers/siblings.
- Model **schema** (entity/attribute *definitions*) may be assumed/provisioned once; **records** are per-test.

---

## Recurring root-cause signatures → fix

| Symptom | Root cause | Fix |
|---|---|---|
| `KeyNotFoundException` in `MetadataCache.ClearAndAddToCache` during `CdpService..ctor`/`ReloadCache` (Setup) | Leaked test entities corrupt the shared model + parallel create/delete races | Purge debris via the Profisee API (deleting an entity cascades its `_DQIssue` companion + drops data tables — never raw SQL); fix the leaking test's cleanup; `[DoNotParallelize]` all model-mutators |
| `"... does not exist. Attribute Name: X"` on create | Test sends an attribute the entity doesn't define (stale test data) OR a missing-but-real attribute | If only tests reference it → remove (stale); if production code uses it → provision the attribute on the instance |
| `8617 ... domain based attribute is not valid. DBACode: Y` | A domain attribute (Category, TemplateId, Scenario) set to a code with no matching record | Use a REAL code (self-provision the referenced record) or omit the attribute; brand-new codes aren't immediately valid domain members |
| `8610 ... incompatible with the attribute length` | Value exceeds the attribute length (e.g. `TemplateData`/`ScenarioData` are `Text(4000)`) | Shrink the test data to fit uncompressed, or store compressed |
| `8603 ... member already exists. RecordCode: N` | Bulk-create with fixed/source codes that linger across runs | Re-code with unique per-run codes + cleanup |
| Retrieved `Name` ≠ created Name (e.g. `WorkloadExecution.Name` = `" for Version "`) | The entity's `Name` is **server-computed**, not settable | Assert identity by `Code`, not `Name` |
| "should be compressed" / decompress → null | Codec migrated **GZIP → BROTLI**; stale test helper only knew `GZIP:` | Make the test's `TemplateStorage` **delegate to production** `TestAuto.Shared.Services.TemplateStorage` (handles BROTLI:, GZIP:, plain, AND double-encoding); use a codec-agnostic `IsCompressedStorage()` (prefix is `BROTLI:` OR `GZIP:`) instead of hard-coding a prefix |
| Migration double-compresses / "0% deserializable" / not idempotent | `ConfigurationMigrationJob` "already compressed?" check tested only `StartsWith("GZIP:")` | Also skip `BROTLI:`. (Note `SerializeForStorage(string)` double-encodes a JSON string; the production reader unwraps it — test readers must too) |
| A just-created record isn't found by a follow-up `GetRecordsAsync` | `GetRecordsAsync` silently caps at the server-default first page (50) | Use `GetAllRecordsAsync(entity, query, pageSize)` |
| ConnEx delete returns **405** | `DELETE /v1/Connect/Configurations/{id}` (path form) is unsupported | Delete via query param: `DELETE /v1/Connect/Configurations?ConfigurationUids={id}` (`ConnExConstants.ConfigurationDeleteParam`; also `IntegrationStrategyUids`, `ServiceProviderUids`); accept 200/201/204/207/404 |
| `"entity does not exist"` for a TestAuto entity that clearly exists | Wrong instance: TestAuto config entities (`TestAutoScenarios/Templates/ValidationLogs`, `WorkloadExecution`, `Scenario`) live in the **ScenarioMgt** instance, NOT the default **Profisee** instance | Build the client with `factory.GetClient(new ScenarioConfiguration(), RestSubjectArea.ScenarioMgt)`; the default `IRestClient`/`IEntityValidationService` are Profisee-bound |
| `No service for type 'X' has been registered` | A test-only/util service (e.g. `EntityTestingUtilities`) isn't in DI | Register it test-side in `BaseTest` (don't pollute the production container) |
| ConnEx import 400 `"Unexpected character ... Path 'importData'"` | `importData` posted as a raw object | Post `importData` as a JSON-encoded **string** |
| Whole DI container fails to build (`ValidateOnBuild` AggregateException) | A string-ctor service got swept into Scrutor auto-registration | Add it to the exclusion lists in the relevant `*ServiceExtensions` |

---

## Skip criteria — don't burn the budget; note and move on (Integration mostly)

- **Env-sensitive perf/timing thresholds** (memory-growth, "completes within Nms", O(1) keyset, throughput) —
  non-deterministic on a loaded box; pass on a clean run. Not code bugs.
- **Run-data-dependent** (matching activity/transaction-id, ConnEx batch status) — need a real job to have run;
  self-provisioning is heavyweight. Skip unless the user wants the full setup.
- **Deep executor/contract mismatches** that need runtime debugging of a production component (e.g. the
  `SqlScriptExecutor`'s source/destination batch routing vs a temp-table test).
- **Running-app serializer/auth** (e.g. `[ApiController]` `[FromBody]` can't bind a `JToken`-bearing model via
  System.Text.Json → 400) — needs a production formatter change; out of scope for a test fix.
- A test whose premise is self-contradictory (e.g. asserts the SPA HTML from a JSON API).

When skipping, say which test and why (one line), and keep going to the next.

---

## Definition of done per category

Re-run the category with `--no-build`; confirm the count dropped and the remaining failures are only the
documented skips. Then move to the next-largest category. A clean tree (`dotnet build` 0 errors) is a hard
gate — never leave the suite non-compiling between iterations.
