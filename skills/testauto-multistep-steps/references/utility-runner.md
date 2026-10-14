# Utility Runner Onboarding, Patterns, and Troubleshooting

Reference for the `testauto-multistep-steps` skill. Loaded on demand — see `SKILL.md` for the decision rules and gotchas that decide whether you need this file.

---

## Utility Runner Onboarding

`MultiStepUtilityScenario` is the scenario class for all utility-runner workloads. It executes steps sequentially, substituting `{{Token}}` values from global and step-level parameters.

### Minimal Config JSON

```json
{
  "ScenarioType": "MultiStepUtilityScenario",
  "ScenarioName": "MyDeployment",
  "CustomParms": {
    "ProfiseeUrl": "https://my-instance.profisee.com",
    "ExportFilePath": "<folder>\\export.zip"
  },
  "Steps": [
    {
      "Type": "CLU",
      "Description": "Export model",
      "Url": "{{ProfiseeUrl}}",
      "TaskType": "EXPORT",
      "FilePath": "{{ExportFilePath}}",
      "TypeHint": "MODEL"
    }
  ]
}
```

### Project Layout

| Path | Purpose |
|---|---|
| `TestAuto.Utilities\` | Main project: executors, step DTOs, scenario class |
| `TestAuto.Utilities\Executors\` | One executor per step type (`CLUExecutor`, `SqlScriptExecutor`, …) |
| `TestAuto.Utilities\Common\DTOs\` | Step DTO classes (`CLUStep`, `SqlStep`, `PowerShellStep`, …) |
| `TestAuto.Utilities\Scripts\` | Shared scripts organized by category |
| `TestAuto.Utilities\Documentation\` | User guides and reference docs |

### Core Concepts

| Concept | Details |
|---|---|
| **Token replacement** | `{{Key}}` in any string property; case-insensitive; step-level params override global |
| `continueOnError` | Per-step flag; when `true`, failure is logged but execution continues |
| **Step sequencing** | Steps execute strictly in declaration order; no branching |
| **Metrics** | Each step emits `UtilityStepDetail`; scenario aggregates via `MetricBatchSummaryBase` |
| **Step content** | Always inline (`sqlScript` / `scriptContent` / `body` / `command`) — no script-file references at runtime |

### Step content is inline (no `ScriptPath`)

Steps do **not** reference script files by path. The file-reference model (`ScriptKey` / `ScriptPath` / `BodyFilePath`) is retired — put the SQL/PowerShell/body directly in the step's inline field.

```jsonc
// SQL step — inline, NOT a ScriptPath
{ "Type": "SQL", "Description": "Validate row counts", "SqlScript": "SELECT COUNT(*) FROM dbo.Imported;" }
```

> A bundled `TestAuto.Utilities/Scripts/` folder still ships (e.g. `SQL/Utility/CreateDatabase.sql`) and is used by the one-time conversion job to *recover and inline* legacy `bodyFilePath` content (see [[testauto-config-store-migration]]) — but it is not a runtime step-content source.

---

## Common Patterns and Troubleshooting (Utility Runner)

### Patterns

**Data Migration Pipeline**

```json
{
  "Steps": [
    { "Type": "CLU", "TaskType": "EXPORT", "FilePath": "{{ExportPath}}", "TypeHint": "DATA" },
    { "Type": "SQL", "Description": "Validate row counts", "SqlScript": "SELECT COUNT(*) FROM dbo.Migrated;" },
    { "Type": "CLU", "TaskType": "IMPORT", "FilePath": "{{ImportPath}}", "TypeHint": "DATA" }
  ]
}
```

**Deployment with Rollback Guard** — export backup first so manual recovery is possible if import fails:

```json
{
  "Steps": [
    { "Type": "CLU", "TaskType": "EXPORT", "FilePath": "{{BackupPath}}", "TypeHint": "ALL" },
    { "Type": "CLU", "TaskType": "IMPORT", "FilePath": "{{DeployPath}}", "TypeHint": "APPLICATION" }
  ]
}
```

**Matching Maintenance Sequence**

```json
{
  "Steps": [
    { "Type": "CLU", "TaskType": "MATCHING_INDEX_REBUILD", "Strategy": "{{Strategy}}", "TimeoutSeconds": 1800 },
    { "Type": "CLU", "TaskType": "MATCHING_PROCESS", "Strategy": "{{Strategy}}", "ClearOptions": "CLEARPRIORRESULTS", "IncludeSurvivorship": true }
  ]
}
```

**Cleanup Pattern**

```json
{
  "Steps": [
    { "Type": "CLU", "TaskType": "MATCHING_INDEX_UNLOAD", "Strategy": "{{Strategy}}" },
    { "Type": "SQL", "SqlScript": "DELETE FROM dbo.MatchingResults;" }
  ]
}
```

**Validation-First Pattern** — check preconditions before running expensive operations:

```json
{
  "Steps": [
    { "Type": "SQL", "Description": "Assert source data ready", "CaptureScalarResult": true, "SqlScript": "SELECT CASE WHEN EXISTS(SELECT 1 FROM dbo.Source) THEN 0 ELSE 1 END;" },
    { "Type": "CLU", "TaskType": "IMPORT", "FilePath": "{{FilePath}}", "TypeHint": "DATA", "TimeoutSeconds": 3600 }
  ]
}
```

### Troubleshooting

| Error / Symptom | Likely Cause | Fix |
|---|---|---|
| `The following tokens were found in the input but have no matching source: {{X}}` | Key missing from `GlobalParameters` / step `Parameters`, or a `$config:`/`$env:` key that resolves to empty | Add the key. Remember there is **no cross-source fallback** — `{{$config:A:B}}` will not fall back to a parameter, and a plain `{{X}}` will not fall back to config |
| HTTP step times out sooner than expected | The inner request timeout is `MaxTimeSeconds ?? TimeoutSeconds` — the old hardcoded 30 s fallback is **gone** | Raise `TimeoutSeconds`, or set `MaxTimeSeconds` when the request needs a different bound from the step |
| SQL step is skipped / "no executor found" | One of `sqlSourceConnectionSecretName` / `sqlDestinationConnectionSecretName` is blank — `CanExecute` requires **both** | Set both (same value is fine for a single-DB step) |
| `Connection string not found for secret name: 'X'` | Secret name not under `ConnectionStrings:` and not one of the three case-sensitive legacy aliases | Add `ConnectionStrings:X`, or use the exact casing `ProfiseeDB` / `MessagingDB` / `MonitorDB` |
| ARCHIVEDATA step errors "Strategy is required" | `FilePath` was supplied instead of `Strategy` | ARCHIVEDATA is `Strategy`-only; `FilePath` is ignored |
| CLU step fails with exit code 1 | Exe path wrong, ClientId wrong, or task config error | Check secrets; run CLU manually to see stderr |
| CLU step hangs past `TimeoutSeconds` | Operation taking longer than expected | Increase `TimeoutSeconds`; use `RefreshIntervalMs` for progress polling |
| PowerShell execution policy error | Unsigned script blocked | Add `-ExecutionPolicy Bypass` in the step config |
| Metrics not appearing | `continueOnError: true` masked a failure | Check step-level `Status` in the scenario result |
| Steps run out of order | JSON array ordering error | Steps execute in declaration order — verify JSON array sequence |

### Debugging Tips

- Run with a single step first to isolate failures.
- Use `continueOnError: true` temporarily during development to see all step outputs before fixing errors.
- Check `UtilityStepDetail` in the metrics output — it captures stdout, stderr, and exit code per step.
- Token replacement is case-insensitive but whitespace-sensitive — trim extra spaces around `{{` and `}}`.

### Best Practices

1. Always export a backup before importing to production.
2. Parameterize all environment-specific values via `CustomParms` — never hardcode URLs or file paths.
3. Use `Description` on every step — it appears in metrics and makes failures traceable.
4. Set `TimeoutSeconds` explicitly on long-running CLU operations instead of relying on the 600s default.
5. Put validation SQL steps before expensive CLU operations to catch data issues early.
6. Use `continueOnError: false` (default) in production — fail fast is safer than partial execution.

---
