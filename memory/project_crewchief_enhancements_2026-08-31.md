---
name: project-crewchief-enhancements-2026-08-31
description: "CrewChief 8-item enhancement batch shipped 8/31 — SQL drop-connections toggle, startOfWeek/dateOnly/dateTime filters, PS output capture, database-names pickers, PS resolved-script preview"
metadata: 
  node_type: memory
  type: project
  originSessionId: 71e3143f-b548-40b3-80c7-3f8cab36bfed
  modified: 2026-08-31T23:29:00.439Z
---

Shipped 2026-08-31 (uncommitted, user commits). Suite 3647/0, solution 0-error.

1. **SQL `sqlDropConnections`** (SqlStep.DropConnections): `Helpers/DropDatabaseGuardInjector.cs` injects `IF DB_ID(N'x') IS NOT NULL ALTER DATABASE [x] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;` before each DROP DATABASE, after token replacement, before AutoWrap. Comment/string/bracket-aware sanitizer (apostrophe inside `[O'Brien]` is NOT a string start — bug found by test). Editor RadzenSwitch.
2. **Token filters**: `startOfWeek` (optional day-name arg, default Monday), `dateOnly` (truncates to midnight AND renders date-only), `dateTime`. startOfMonth/endOfMonth now set dateOnly=true (render `2026-08-01` not `...T00:00:00`). Builder picker picks these up automatically via DescribeAll/Arity parity.
3. **PowerShell `outputParameterName`**: orchestrator copies globals to a run-local OrdinalIgnoreCase dict at ExecuteScenarioAsync start (caller dict never mutated), and after a succeeded PowerShellStep writes trimmed StandardOutput (pre-masking) under that name — later steps get it via normal merge. Validation rejects reserved chars via TokenShapes.IsReservedInParameterName. **Cross-step propagation**: WorkloadEngine runs ONE orchestrator call per step, so captures also surface on `UtilityScenarioResult.CapturedParameters` and the engine folds them into a run-local globals copy between calls (never into the stored workload).
4. **`ReferenceDataSets.DatabaseNames`** ("database-names" — the refkv.json shipped set already existed, const didn't). **ServerNameEditor generalized**: new params ReferenceType/Label/ReferencePlaceholder/SecretModePlaceholder (defaults = old behavior); mode inference scoped to ReferenceType. Wired as Database Name picker on DB-ops + SetApiKey editors.
5. **SetApiKey dbname `{{token}}`**: executor path proven working by new tests ({{Param}} and {{$ref:database-names:...}} both resolve into Initial Catalog). If user hit "does not work" live, likely cause: set not installed/flagged replaceable on that box, or resolver null — engine throws fail-fast naming the token.
6. **PowerShell resolved-script preview**: collapsible panel, `BuildPowerShellPreview(reveal)` uses IValuePreviewService.Describe (masks secrets, Deferred = raw script + reason comment), SecretRevealToggle + Copy, same grant flow as CLU/Install/Configure previews.
7. **Item 8 audit (two passes — first missed untyped `<input class="form-control">`)**: converted CLU Url, HTTP Url, ConnEx BaseUrl, MapShare SharePath → unrestricted SecretValueEditor; HealthGate RecycleServiceName → ServiceNameEditor (new `LoadServicesForHealthGateAsync` local/ambient enumeration + `HealthGateServiceContextKey`); RunWorkloadStep WorkloadName → datalist of saved workload names (new `[Inject] IWorkloadFileStore` on StepEditorCard + TryAdd registration in SecretCatalogTestServices). Already pickers: Teams WebhookUrl, HealthGate Url, ConnEx ApiKey, SQL/DB-ops/SetApiKey conns+creds. Deliberately text: command lines (cmd/curl), file paths (CLU FilePath, MSI path has Browse), CSV codes, ports, wait seconds, email To/Subject/Body, Teams Title/Message, ConnEx ResourceId/CLU Strategy (RefDataPicker assist), MapShare DriveLetter (drive-map datalist).

Docs updated: 21_WorkloadTokens.md, 12_StepGuideSql.md, 13_StepGuidePowerShell.md (new "Capturing output" section), 21_StepGuideDatabaseOperations.md, 26_StepGuideSetApiKey.md.

GateGuard hook active this session: denies FIRST write per file, retry succeeds.

**300m bundle RESOLVED 8/31**: tokens were never the problem — Run-As driver launched bare `pwsh.exe` (`preferWindowsPowerShell:false` → no probe/fallback on the credentialed path, deliberate, PowerShellScriptExecutor.cs:416) and PowerShell 7.6.5 on CORPVMHA1 was mis-installed (no `C:\Program Files\PowerShell`, not machine-resolvable). User reinstalled pwsh correctly → fixed. Improvement candidate (not done): LocalRunAs driver error should NAME the executable+machine ("pwsh.exe not found — install PS7 machine-wide or enable Use Windows PowerShell") instead of raw "The system cannot find the file specified".

**Original diagnosis trail (kept for the useful facts)**: engine chain PROVEN correct — new test `ResolveSpecial_BundleShapedRefAndParamChain_ResolvesIntoTheScriptBody` replicates the bundle's $ref + param-in-param chain and passes. Two real failure modes: (a) `{{$ref:configuration-values:profisee_installed_path}}` is OPERATOR-ADDED, not shipped — present on installed C:\Deploy instance, absent elsewhere; missing → step fail-fasts naming the token; (b) **silent literal leak**: `PowerShellScriptExecutor.cs:143` (and `SqlScriptExecutor` step 3) skip templating entirely when merged params are EMPTY — script runs with literal `{{...}}`, zero validation. Happens when a step runs without workload globals (standalone from Steps library, etc.). Hardening candidate: always call ReplaceTokens. No run record of the workload on this box (ran on greendot lab box).
