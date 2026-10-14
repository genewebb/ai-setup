# CLU Step — Full TaskType Parameter Reference

Reference for the `testauto-multistep-steps` skill. Loaded on demand — see `SKILL.md` for the decision rules and gotchas that decide whether you need this file.

---

## CLU Task Type Parameters — Full Reference

Each task type maps to a `CLUStep` entry. Only the parameters relevant to that type are required. Use `AdvancedArguments` for flags not yet exposed as first-class properties.

### IMPORT

```json
{
  "Type": "CLU",
  "Description": "Import model/data package",
  "Url": "{{ProfiseeUrl}}",
  "TaskType": "IMPORT",
  "FilePath": "{{ImportFilePath}}",
  "TypeHint": "ALL",
  "IncludeMemberships": true,
  "IncludeAssignments": false
}
```

| Parameter | Required | Options | Notes |
|---|---|---|---|
| `FilePath` | Yes | — | Path to .zip or .profisee file |
| `TypeHint` | Yes | `ALL`, `MODEL`, `APPLICATION`, `DATA`, `RULES` | Scope of import |
| `ReportType` | No | — | Optional report output format |
| `IncludeMemberships` | No | true/false | Include user memberships |
| `IncludeAssignments` | No | true/false | Include workflow assignments |

### EXPORT

```json
{
  "Type": "CLU",
  "Description": "Export model and data",
  "Url": "{{ProfiseeUrl}}",
  "TaskType": "EXPORT",
  "FilePath": "{{ExportFilePath}}",
  "TypeHint": "ALL"
}
```

Parameters: `FilePath` (required), `TypeHint` (required), `ReportType` (optional).

### RULES_EXPORT

```json
{
  "Type": "CLU",
  "Description": "Export business rules for entity",
  "Url": "{{ProfiseeUrl}}",
  "TaskType": "RULES_EXPORT",
  "FilePath": "{{RulesFilePath}}",
  "Entity": "{{EntityName}}"
}
```

Parameters: `FilePath` (required), `Entity` (required — the source entity UID or name).

### RULES_IMPORT

```json
{
  "Type": "CLU",
  "Description": "Import business rules",
  "Url": "{{ProfiseeUrl}}",
  "TaskType": "RULES_IMPORT",
  "FilePath": "{{RulesFilePath}}"
}
```

Parameters: `FilePath` (required).

### ARCHIVEDATA

```json
{
  "Type": "CLU",
  "Description": "Archive data using named strategy",
  "Url": "{{ProfiseeUrl}}",
  "TaskType": "ARCHIVEDATA",
  "Strategy": "{{ArchiveStrategyName}}"
}
```

Parameters: `Strategy` (required — archive strategy name configured in Profisee).

### DEPLOYDATA

```json
{
  "Type": "CLU",
  "Description": "Deploy a data package",
  "Url": "{{ProfiseeUrl}}",
  "TaskType": "DEPLOYDATA",
  "FilePath": "{{DataPackagePath}}"
}
```

Parameters: `FilePath` (required — path to the data package).

### MATCHING_PROCESS

```json
{
  "Type": "CLU",
  "Description": "Run full matching with survivorship",
  "Url": "{{ProfiseeUrl}}",
  "TaskType": "MATCHING_PROCESS",
  "Strategy": "{{StrategyName}}",
  "ClearOptions": "CLEARPRIORRESULTS",
  "IncludeSurvivorship": true,
  "RefreshIntervalMs": 5000
}
```

| ClearOptions Value | Behavior |
|---|---|
| `CLEARPRIORRESULTS` | Clear prior match results before processing |
| `CLEARALLPRIORRESULTS` | Clear all prior results including approved |
| `EXCLUDEAPPROVED` | Skip records already approved |
| `EXCLUDEUSERMAPPED` | Skip user-mapped records |

### MATCHING_SURVIVORSHIP_ONLY

```json
{
  "Type": "CLU",
  "TaskType": "MATCHING_SURVIVORSHIP_ONLY",
  "Strategy": "{{StrategyName}}",
  "RefreshIntervalMs": 5000
}
```

Parameters: `Strategy` (required), `RefreshIntervalMs` (optional, ms between polls).

### MATCHING_INDEX_REBUILD / MATCHING_INDEX_UNLOAD / MATCHING_CANCEL

```json
{
  "Type": "CLU",
  "TaskType": "MATCHING_INDEX_REBUILD",
  "Strategy": "{{StrategyName}}",
  "TimeoutSeconds": 1800
}
```

All three require only `Strategy`. `MATCHING_INDEX_REBUILD` is long-running — use `TimeoutSeconds: 1800` minimum.

### Timeout Recommendations

| Task Type | Small Data | Large Data |
|---|---|---|
| EXPORT | 600s | 1200–1800s |
| IMPORT | 600s | 1800–3600s |
| MATCHING_PROCESS | 3600s | 7200–14400s |
| MATCHING_INDEX_REBUILD | 1800s | 1800s |
| RULES_EXPORT / RULES_IMPORT | 600s | 600s |

---

## CLU Secrets Configuration

Two secrets are required before any CLU step will execute:

| Secret Key | Value | Example |
|---|---|---|
| `Profisee:CLU:Path` | Full path to CLU exe | `%ProgramFiles%\Profisee\Master Data Maestro Utilities\26.1.0\Profisee.MasterDataMaestro.Utilities.exe` |
| `Profisee:CLU:ClientId` | API Client ID GUID | `12345678-1234-1234-1234-123456789abc` |

### Import via JSON (Recommended)

<!-- example-paths -->
```json
{
  "Profisee:CLU:Path": "C:\\Program Files\\Profisee\\Master Data Maestro Utilities\\26.1.0\\Profisee.MasterDataMaestro.Utilities.exe",
  "Profisee:CLU:ClientId": "12345678-1234-1234-1234-123456789abc"
}
```

Navigate to the **Secrets** page in the TestAuto Web UI → Import → paste the JSON → Save.

### Edit via Web UI

Navigate to `/secrets` in the TestAuto Web UI and set each key directly.

### Verification

- **Green badge** on the Secrets page = configured and valid.
- **Red badge** = missing or invalid. Check the key name exactly — colon separators, no trailing spaces.

### Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `CLU path not found` | Exe path wrong or CLU not installed | Verify path exists; check CLU version folder |
| `ClientId GUID invalid` | Wrong format or placeholder value | Must be a valid GUID, no braces |
| Secrets not loading after edit | App not restarted | Restart TestAuto application |
| Bootstrap error on fresh machine | Machine profile not initialized | Run machine bootstrap first |

Secrets are AES-256 encrypted in the `TestAutoSecrets` entity. Each machine has its own DPAPI-protected master password — secrets are machine-specific unless migrated via the export/import flow.

---
