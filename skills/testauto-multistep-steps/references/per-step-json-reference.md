# Per-Step JSON Configuration Reference

Reference for the `testauto-multistep-steps` skill. Loaded on demand — see `SKILL.md` for the decision rules and gotchas that decide whether you need this file.

---

## Per-Step JSON Configuration Reference

Minimal working configs for each step type. Copy, paste, and fill in the required fields. All examples assume a top-level `"Steps": [...]` array; wrap in a full config with `GlobalParameters` as needed.

---

### HTTP Request Step (`HttpRequestStep` / `CURL` / `Http`)

**Minimal GET:**

```json
{
  "Type": "HttpRequestStep",
  "Description": "Fetch a resource",
  "Url": "{{$config:RestClients:Profisee:BaseUrl}}rest/v1/Records/MyEntity",
  "Method": "GET",
  "Headers": {
    "x-api-key": "{{$config:RestClients:Profisee:ApiKey}}"
  },
  "ExpectedStatusCodes": [200]
}
```

**Minimal POST with body:**

```json
{
  "Type": "HttpRequestStep",
  "Description": "Create a record",
  "Url": "{{$config:RestClients:Profisee:BaseUrl}}rest/v1/Records/MyEntity",
  "Method": "POST",
  "Headers": {
    "Content-Type": "application/json-patch+json",
    "Accept": "application/json",
    "x-api-key": "{{$config:RestClients:Profisee:ApiKey}}"
  },
  "Body": "[{\"Code\": \"001\", \"Name\": \"Sample\"}]",
  "ExpectedStatusCodes": [200, 201]
}
```

**Key notes:**

- `Url` is the only truly required field beyond `Type`. All other fields are optional but you almost always need `Headers` for auth.
- `ExpectedStatusCodes` defaults to any 2xx. Specify explicitly for precision — especially useful for delete steps that should accept `[200, 204, 404]`.
- Profisee REST v1 record creation uses `application/json-patch+json`, not `application/json`.
- `VerifySsl: false` is needed in dev environments with self-signed certs.
- `Body` is inline only — there is no `BodyFilePath` (file references retired). `OutputFile` still saves the *response* to disk.
- `MaxTimeSeconds` is the inner HTTP request timeout and **falls back to the step's `TimeoutSeconds` when unset** (`MaxTimeSeconds ?? TimeoutSeconds` at `HttpRequestStep.cs:184`). The old hardcoded 30 s fallback was removed in 2026-08. The outer process kill is `max(TimeoutSeconds, MaxTimeSeconds ?? 0) + 5` via `HttpStepTimeoutCalculator`. For anything slow, raising `TimeoutSeconds` alone is now sufficient.
- `UseRestMethod` (default `true`) picks `Invoke-RestMethod`; set `false` to emit a `curl.exe` command instead (and to use `CustomCurlArgs`).
- Use `"CURL"` type alias only in legacy configs — prefer `"HttpRequestStep"` for new work.

---

### SQL Step (`SqlStep` / `SQL`)

**Minimal connectivity check (read-only):**

```json
{
  "Type": "SqlStep",
  "Description": "Verify database connectivity",
  "SqlScript": "SELECT 1 AS ConnectionTest",
  "sqlSourceConnectionSecretName": "MyDb",
  "sqlDestinationConnectionSecretName": "MyDb",
  "UseTransaction": false,
  "CaptureScalarResult": true,
  "TimeoutSeconds": 30
}
```

**Minimal write operation:**

```json
{
  "Type": "SqlStep",
  "Description": "Insert audit log entry",
  "SqlScript": "INSERT INTO AuditLog (Event, Timestamp) VALUES ('Run', GETUTCDATE())",
  "sqlSourceConnectionSecretName": "AppDb",
  "sqlDestinationConnectionSecretName": "AppDb",
  "UseTransaction": true
}
```

**Parameterized inline script (token replacement):**

```json
{
  "Type": "SQL",
  "Description": "Count rows in a table",
  "SqlScript": "SELECT COUNT(*) FROM {{TableName}}",
  "sqlSourceConnectionSecretName": "ProfiseeConnection",
  "sqlDestinationConnectionSecretName": "ProfiseeConnection",
  "CaptureScalarResult": true,
  "Parameters": {
    "TableName": "Customer"
  }
}
```

**Key notes:**

- Both `sqlSourceConnectionSecretName` and `sqlDestinationConnectionSecretName` are required in practice — even for read-only queries. The executor routes to source when `CaptureScalarResult: true`, destination otherwise.
- `UseTransaction: false` is required for DDL statements (`CREATE DATABASE`, `ALTER DATABASE`, `BACKUP`, `RESTORE`) — these cannot run inside a transaction.
- `SqlScript` is the only content source — `ScriptKey`/`ScriptPath` file references are retired.
- `AutoWrapPassFailCode: true` (default) wraps the SQL in TRY/CATCH and returns 0/1. Set `false` for scripts that manage their own error handling or use `RAISERROR`.
  - On failure the wrapper now also **surfaces the real SQL error**, so a failing step reports the cause instead of an opaque code. The CATCH captures `ERROR_MESSAGE()` and emits it two ways: (1) `RAISERROR(N'%s', 10, 1, @msg) WITH NOWAIT` — severity 10 is *informational* (does not abort), fires `SqlConnection.InfoMessage` → Serilog immediately; (2) a second result column (`SELECT @PassFailCode AS PassFailCode, @PassFailErrorMessage AS PassFailErrorMessage`) which the executor reads into `StepExecutionResult.PassFailErrorDetail`. When non-null, it is appended to the step's `ErrorMessage` (`… SQL error: <detail>`). The `'%s'` format keeps any literal `%` in the error text intact.
- `SqlCommandTimeoutSeconds: 0` = infinite SQL command timeout. Distinct from `TimeoutSeconds` which is the step wrapper timeout.
- `GO` batch splitting works on the inline `SqlScript` (`GoBatchSplitter` runs on the content unconditionally).

---

### PowerShell Step (`PowerShellStep` / `PS`)

**Minimal inline script:**

```json
{
  "Type": "PowerShellStep",
  "Description": "Check free disk space",
  "ScriptContent": "$drive = Get-PSDrive C; Write-Output \"Free: $([math]::Round($drive.Free / 1GB, 2)) GB\"",
  "TimeoutSeconds": 15
}
```

**Parameterized inline script (token replacement):**

```json
{
  "Type": "PS",
  "Description": "Assert minimum free memory",
  "ScriptContent": "$min = {{MinMemoryGB}}; $free = (Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory/1MB; if ($free -lt $min) { exit 1 }",
  "TimeoutSeconds": 30,
  "Parameters": {
    "MinMemoryGB": "4"
  }
}
```

**Minimal with environment variables:**

```json
{
  "Type": "PowerShellStep",
  "Description": "Run smoke tests",
  "ScriptContent": "Write-Output \"Env: $env:TEST_ENVIRONMENT\"; ./Invoke-SmokeTests.ps1",
  "TimeoutSeconds": 300,
  "EnvironmentVariables": {
    "TEST_ENVIRONMENT": "{{Environment}}",
    "SKIP_INTEGRATION_TESTS": "true"
  }
}
```

**Key notes:**

- Execution policy defaults to `"Bypass"` — you rarely need to change it.
- By default, `pwsh` (PowerShell Core 7.x) is tried first; `powershell.exe` (5.1) is the fallback. Set `PreferWindowsPowerShell: true` when you need Active Directory or other Windows-only modules.
- `TreatStderrAsError: true` is the default. If your script writes informational output to stderr (some cmdlets do), set `false` to avoid false failures.
- `SuccessExitCodes` defaults to `[0]` only. For scripts that use non-zero clean exits, specify them explicitly.
- `ScriptContent` is the only content source — `ScriptKey` file references are retired. Put the script inline (call out to a bundled helper from within the inline content if needed).

---

### Command Line Step (`CommandLineStep` / `CLI` / `CMD`)

**Minimal ping:**

```json
{
  "Type": "CommandLineStep",
  "Description": "Check network connectivity",
  "Command": "ping",
  "Args": ["-n", "1", "{{ServerName}}"],
  "SuccessExitCodes": [0],
  "TimeoutSeconds": 10
}
```

**Minimal dotnet build:**

```json
{
  "Type": "CLI",
  "Description": "Build the application",
  "Command": "dotnet",
  "Args": ["build", "--configuration", "Release"],
  "WorkingDirectory": "{{SolutionPath}}",
  "SuccessExitCodes": [0],
  "TimeoutSeconds": 300
}
```

**Minimal robocopy (multi success codes):**

```json
{
  "Type": "CommandLineStep",
  "Description": "Copy deployment files",
  "Command": "robocopy",
  "Args": ["{{SourcePath}}", "{{DestPath}}", "/E", "/R:1", "/W:1"],
  "SuccessExitCodes": [0, 1, 2, 3],
  "TimeoutSeconds": 300
}
```

**Key notes:**

- `Command` is required. `Args` is an array — each element is a separate argument. Spaces within an element are preserved (no extra quoting needed).
- `SuccessExitCodes` defaults to `[0]`. Many tools use non-zero codes for success: robocopy uses 0-3, findstr returns 1 when there is no match. Always check the tool's conventions.
- Pipes, redirects, and `&&` require `UseShell: true` (runs through `cmd.exe`). Alternatively, use `"Command": "cmd"` with `"Args": ["/c", "your | piped | command"]`.
- `WaitForExit: false` for fire-and-forget (the step completes immediately without waiting for the process).
- `CreateNoWindow: true` is the default — suppresses the launched process's console window on Windows. The executor always runs with `UseShellExecute=false` (even when `UseShell: true`, which only wraps the command in `cmd`/`pwsh`/`sh`), so `CreateNoWindow` is applied to the process **regardless of the `UseShell` setting**.

---

### CLU Step (`CLUStep` / `CLU`)

**Minimal data export:**

```json
{
  "Type": "CLU",
  "Description": "Export entity data",
  "Url": "{{ProfiseeUrl}}",
  "TaskType": "EXPORT",
  "FilePath": "{{ExportDirectory}}\\Customer_Export.zip",
  "TypeHint": "DATA",
  "TimeoutSeconds": 1200
}
```

**Minimal data import:**

```json
{
  "Type": "CLU",
  "Description": "Import entity data",
  "Url": "{{ProfiseeUrl}}",
  "TaskType": "IMPORT",
  "FilePath": "{{ImportDirectory}}\\CustomerData.zip",
  "TypeHint": "DATA",
  "TimeoutSeconds": 900
}
```

**Minimal matching sequence (index rebuild then run):**

```json
{
  "Type": "CLU",
  "Description": "Rebuild matching index",
  "Url": "{{ProfiseeUrl}}",
  "TaskType": "MATCHING_INDEX_REBUILD",
  "Strategy": "{{MatchingStrategy}}",
  "TimeoutSeconds": 1800
},
{
  "Type": "CLU",
  "Description": "Run matching with survivorship",
  "Url": "{{ProfiseeUrl}}",
  "TaskType": "MATCHING_PROCESS",
  "Strategy": "{{MatchingStrategy}}",
  "ClearOptions": "CLEARPRIORRESULTS",
  "IncludeSurvivorship": true,
  "RefreshIntervalMs": 3000,
  "TimeoutSeconds": 7200
}
```

**Key notes:**

- `Url` and `TaskType` are always required alongside `Type`.
- `FilePath` is required for `IMPORT`, `EXPORT`, `RULES_EXPORT`, `RULES_IMPORT`, and `DEPLOYDATA`.
- ⚠️ **`ARCHIVEDATA` takes `Strategy`, NOT `FilePath`.** `CLUCommandBuilder.ValidateArchiveData` errors with *"Strategy is required for ARCHIVEDATA operations"* (`CLUCommandBuilder.cs:235-239`) and `BuildArchiveDataArguments` emits only `-strategy <Strategy>` (`:320-325`) — a `FilePath` you set on an ARCHIVEDATA step is silently ignored. (The `FilePath` XML doc on `CLUStep.cs:27` lists ARCHIVEDATA among file operations; that comment is wrong.)
- `Strategy` is required for `ARCHIVEDATA`, `MATCHING_PROCESS`, `MATCHING_SURVIVORSHIP_ONLY`, `MATCHING_INDEX_REBUILD`, `MATCHING_INDEX_UNLOAD`, and `MATCHING_CANCEL`.
- **Always rebuild the index before running matching** — stale indexes produce incorrect results.
- `RefreshIntervalMs` (e.g., `3000`) enables polling status updates during long matching runs. Without it the step waits silently.
- Matching process timeouts should be generous — large datasets can take hours. Use `TimeoutSeconds: 7200` (2 hours) or more for production-scale strategies.
- `ClearOptions: "CLEARPRIORRESULTS"` removes previous match results before the new run. Almost always set this for test scenarios to avoid stale data.
- CLU path and ClientId come from secrets (`Profisee:CLU:Path`, `Profisee:CLU:ClientId`) — not configured in the step.

---

### ConnEx Step (`ConnExStep` / `ConnEx`)

**Minimal import from artifact file:**

```json
{
  "Type": "ConnEx",
  "Description": "Import SQL Server service configuration",
  "ArtifactFile": "connex-artifacts/SqlServer.ServiceConfiguration.json",
  "Parameters": {
    "ServerName": "{{ServerName}}",
    "Database": "{{Database}}",
    "UsernameVault": "{{$config:RestClients:Connect:SqlUser}}",
    "PasswordVault": "{{$config:RestClients:Connect:SqlPass}}"
  }
}
```

**Minimal export to file:**

```json
{
  "Type": "ConnEx",
  "Description": "Export service configuration",
  "Operation": "Export",
  "ResourceType": "ServiceConfiguration",
  "ResourceId": "fab8726c-cb32-4bae-8388-01c5421bc625",
  "OutputFile": "exports/MyConfig.json"
}
```

**Minimal delete:**

```json
{
  "Type": "ConnEx",
  "Description": "Delete retired integration strategy",
  "Operation": "Delete",
  "ResourceType": "IntegrationStrategy",
  "ResourceId": "a0b1c2d3-e4f5-6789-abcd-ef0123456789",
  "ExpectedStatusCodes": [200, 204]
}
```

**Minimal dry run (validate without executing):**

```json
{
  "Type": "ConnEx",
  "Description": "Validate artifact before deploy",
  "ArtifactFile": "connex-artifacts/SqlServer.ServiceConfiguration.json",
  "DryRun": true,
  "Parameters": {
    "ServerName": "CORPSQL03.corp.profisee.com",
    "Database": "ModelSource"
  }
}
```

**Key notes:**

- For `Import` (the default `Operation`), provide **exactly one** of `ArtifactFile` (path to a JSON template) or `ArtifactJson` (inline JSON) — setting both or neither means no executor accepts the step. **Inline `ArtifactJson` is preferred when it fits** (compressed scenario data under the 4,000-char attribute limit): the artifact travels with the scenario and is portable across machines. Use `ArtifactFile` only when the artifact is too large to inline. Either way, keep credentials as `{{token}}` parameters, not literals in the artifact.
- Token replacement runs inside the artifact JSON content. This is how server names and credentials are injected into artifact templates.
- `ResourceType` is auto-detected from the artifact structure for imports. For export/delete, specify it explicitly: `"ServiceConfiguration"`, `"IntegrationStrategy"`, or `"ServiceProvider"`.
- `BaseUrl` and `ApiKey` default to `$config:RestClients:Connect:BaseUrl` / `ApiKey` — only override when targeting a different environment in the same scenario.
- **Import service configurations before integration strategies** — strategies reference service configs and will fail if the service config doesn't exist yet.
- `DryRun: true` validates everything (token replacement, artifact parsing, API URL resolution) but stops before the HTTP call. Use this to catch typos and missing tokens before a deployment run.
- `ExpectedStatusCodes` defaults to `[200, 201, 204]`. Adjust for delete operations which commonly return `204`.

---

### Monitor Step (`MonitorStep` / `Monitor`)

**Minimal milestone marker:**

```json
{
  "Type": "Monitor",
  "Description": "Log workflow start",
  "Message": "Starting {{WorkflowName}} on {{Environment}}"
}
```

**Minimal with custom activity type:**

```json
{
  "Type": "MonitorStep",
  "Message": "Matching complete for strategy {{Strategy}}",
  "Parameters": {
    "ActivityType": "MatchingComplete",
    "Strategy": "CustomerDuplicateDetection"
  }
}
```

**Bookend pattern (place at start and end of long workflows):**

```json
{
  "Type": "Monitor",
  "Message": "=== START: {{WorkflowName}} ===",
  "ContinueOnError": true
},
```

```json
{
  "Type": "Monitor",
  "Message": "=== END: {{WorkflowName}} ===",
  "ContinueOnError": true
}
```

**Key notes:**

- `Message` is the only required field beyond `Type`. It supports `{{token}}` replacement.
- `ActivityType` is set via the `Parameters` dictionary (not a top-level property). The key is `"ActivityType"`.
- The existing skill note is important: Monitor uses NServiceBus `LogManager`, not Serilog — quieting its log noise is an NServiceBus log-level concern, not a Serilog source-context filter.
- Always set `ContinueOnError: true` on Monitor steps that bookend risky operations — a monitoring failure should never block the actual work.
- Steps always succeed unless the monitoring infrastructure is unavailable. Don't use Monitor steps as a substitute for real error handling.
- Keep messages meaningful: log major milestones, not every trivial action. Too many Monitor steps add noise to the execution history.
