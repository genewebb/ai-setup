---
name: speedmerchants-db-migration
description: >
  Compare record counts between the Speed Merchants source (backup) and target (prod) SQL databases,
  identify missing data by version or category, and migrate missing records via PowerShell
  SqlBulkCopy. Use when asked to compare source vs target, find missing records, sync backup and
  prod, check counts by version, migrate records into the staging table, or "what's missing from
  target".
---

# Speed Merchants DB Migration

## Servers

| Alias | MCP server (tools are `mcp__<server>__execute_query`, etc.) | Database |
|---|---|---|
| **source** | `speedmerchants-prod-mssql-backup` | `pc-speedmr-prd-db-workflow-cleanup` |
| **target** | `speedmerchants-prod-mssql` | prod SpeedMerchants DB (`pc-speedmr-prd-db`) |
| local | `speedmerchants-local-mssql` | `speedmerchants` on `CORPLTR94` (Windows auth) |

Verified against the live `mcpServers` block in `~/.claude.json` (2026-07-27). Server names carry
**no `user-` prefix**. Both prod servers run `mcp-alchemy` over pyodbc; the target server takes its
connection string from the `SPEEDMERCHANTS_PROD_DB_URL` environment variable, and the source
(backup) server has its own `DB_URL` already configured. Re-read `~/.claude.json` if a tool call
fails with an unknown-server error — aliases change.

**Azure SQL host**: `wus2-pc-profisee-sqlserver-0.database.windows.net`

> [!danger] Never put credentials in this skill, a script, or a chat message
> The SQL login and password are **not** recorded here and must not be added. Read them from the
> already-configured MCP `DB_URL` entries in `~/.claude.json`, from the `SPEEDMERCHANTS_PROD_DB_URL`
> environment variable, or from the user's secret store under `{SecretsDir}`. When a
> script needs them, pass them in at run time (prompt, `-Credential`, or environment variable) —
> do not hardcode, do not echo, do not paste into documentation.

> Azure SQL blocks cross-database queries (error 40515) — never attempt 3-part `[db].schema.table`
> references across databases. All migration must go through PowerShell.

## Standard Versions to Compare

When the user asks for a version comparison without specifying, default to:
`25R1`, `25R2`, `25R3`, `25R4`, `26R1`, `26R2P`

## Workflow

### Step 1 — Compare counts by version

Query both MCP servers in parallel. Join to `data.tProfiseeVersion` to resolve the int FK to a readable Code.

```sql
SELECT pv.Code AS ProfiseeVersion, COUNT(*) AS Count
FROM data.tYourTable src
JOIN data.tProfiseeVersion pv ON pv.ID = src.ProfiseeVersion
WHERE pv.Code IN ('25R1','25R2','25R3','25R4','26R1','26R2P')
GROUP BY pv.Code
ORDER BY pv.Code
```

Present as a side-by-side table: `ProfiseeVersion | Source | Target | Match`.
Flag any row where counts differ or target is 0.

### Step 2 — Identify FK columns (before writing migration script)

The staging table (`stg.t{Entity}_Merge`) stores FK columns as **nvarchar Code values**, not int IDs.
Query the source to discover which columns need lookup resolution:

```sql
SELECT COL_NAME(fkc.parent_object_id, fkc.parent_column_id) AS SourceColumn,
       OBJECT_NAME(fkc.referenced_object_id) AS RefTable
FROM sys.foreign_keys fk
JOIN sys.foreign_key_columns fkc ON fk.object_id = fkc.constraint_object_id
WHERE fk.parent_object_id = OBJECT_ID('data.tYourTable')
ORDER BY SourceColumn
```

Common lookup tables and their pattern:
- `tProfiseeVersion`, `tWorkload`, `tScenario`, `tWorkloadExecution`, `tExecutionStatus`,
  `tHttpRequestType`, `tServerProfile` — join on `ID`, use `Code`
- `tYesNo` — used for boolean-style columns (IsBatchCrud, IsCodeLookup, RequestWasFiltered, etc.)

### Step 3 — Check staging table schema

```sql
SELECT COLUMN_NAME, DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'stg' AND TABLE_NAME = 't{Entity}_Merge'
ORDER BY ORDINAL_POSITION
```

Map each source column to its staging equivalent. Note that staging columns are nvarchar where
source has int FKs. The `NewCode` column in staging has no source equivalent — set to `NULL`.

### Step 4 — Write the PowerShell migration script

Save to `{ScratchRoot}\Migrate-{TableName}.ps1`. The script must take the SQL login as a **mandatory
`[pscredential]`** — never a default string literal, never a hardcoded password. Use this template:

```powershell
#Requires -Version 7.0
param(
    [string]$SqlServer  = 'wus2-pc-profisee-sqlserver-0.database.windows.net',
    [string]$SourceDb   = 'pc-speedmr-prd-db-workflow-cleanup',
    [string]$TargetDb   = 'pc-speedmr-prd-db',
    # No credential defaults. Supply -SqlCredential, or set $env:SPEEDMERCHANTS_SQL_USER /
    # $env:SPEEDMERCHANTS_SQL_PASSWORD before running. Nothing secret is stored in this file.
    [Parameter(Mandatory)]
    [pscredential]$SqlCredential,
    [int]$BatchSize     = 500,
    [switch]$WhatIf
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$user       = $SqlCredential.UserName
$plainPw    = $SqlCredential.GetNetworkCredential().Password
$srcConnStr = "Server=$SqlServer;Database=$SourceDb;User Id=$user;Password=$plainPw;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
$tgtConnStr = "Server=$SqlServer;Database=$TargetDb;User Id=$user;Password=$plainPw;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"

$sourceQuery = @"
SELECT
    src.ID,
    src.Code,
    CAST(NULL AS nvarchar(100)) AS NewCode,
    src.Name,
    -- Resolve each int FK column via LEFT JOIN:
    pv.Code  AS ProfiseeVersion,
    -- ... all other columns ...
FROM data.tYourTable src
LEFT JOIN data.tProfiseeVersion   pv  ON pv.ID  = src.ProfiseeVersion
-- ... other joins ...
WHERE src.ProfiseeVersion = :versionId   -- replace with the int ID
ORDER BY src.ID
"@

# List every column in staging table order
$stagingColumns = @('ID','Code','NewCode','Name','ProfiseeVersion', <# ... #>)

$srcConn = $null; $tgtConn = $null; $reader = $null
try {
    Write-Host "Connecting to source ($SourceDb)..."
    $srcConn = [System.Data.SqlClient.SqlConnection]::new($srcConnStr)
    $srcConn.Open()

    if ($WhatIf) {
        $cntCmd = $srcConn.CreateCommand()
        $cntCmd.CommandText = "SELECT COUNT(*) FROM data.tYourTable WHERE ProfiseeVersion = <id>"
        $cntCmd.CommandTimeout = 60
        Write-Host "WhatIf: $($cntCmd.ExecuteScalar()) rows would be inserted" -ForegroundColor Cyan
        return
    }

    Write-Host "Connecting to target ($TargetDb)..."
    $tgtConn = [System.Data.SqlClient.SqlConnection]::new($tgtConnStr)
    $tgtConn.Open()

    $cmd = $srcConn.CreateCommand()
    $cmd.CommandText = $sourceQuery
    $cmd.CommandTimeout = 300
    $reader = $cmd.ExecuteReader()

    $bulk = [System.Data.SqlClient.SqlBulkCopy]::new($tgtConn)
    $bulk.DestinationTableName = 'stg.tYourTable_Merge'
    $bulk.BatchSize = $BatchSize
    $bulk.BulkCopyTimeout = 600
    $bulk.NotifyAfter = $BatchSize

    foreach ($col in $stagingColumns) { $null = $bulk.ColumnMappings.Add($col, $col) }

    $bulk.add_SqlRowsCopied({ param($s,$e); Write-Host "  ...copied $($e.RowsCopied) rows" -ForegroundColor DarkCyan })

    Write-Host "Bulk copying to stg.tYourTable_Merge (batch size: $BatchSize)..."
    $bulk.WriteToServer($reader)
    Write-Host "Migration complete." -ForegroundColor Green

    $reader.Close(); $reader = $null
    $v = $tgtConn.CreateCommand()
    $v.CommandText = "SELECT COUNT(*) FROM stg.tYourTable_Merge WHERE ProfiseeVersion = '<Code>'"
    Write-Host "Target staging rows: $($v.ExecuteScalar())" -ForegroundColor Green
}
finally {
    if ($reader -and -not $reader.IsClosed) { $reader.Close() }
    if ($srcConn -and $srcConn.State -eq 'Open') { $srcConn.Close() }
    if ($tgtConn -and $tgtConn.State -eq 'Open') { $tgtConn.Close() }
}
```

**Key points:**
- Use `SqlBulkCopy` — not batched INSERTs — for 10k+ rows
- Always use explicit `ColumnMappings` by name (not positional)
- `WhatIf` switch is useful before committing
- Staging rows are consumed by the Profisee merge process almost immediately — an empty staging
  table after the script completes is normal; verify by checking `data.t{Entity}` on the target

### Step 5 — Verify after migration

Re-query both DBs with the same count query from Step 1 and confirm all versions match.
If staging is empty but `data.t{Entity}` now has the expected count, the Profisee merge process
already ran — that's the successful outcome.

### Step 6 — Rebuild perfDashboard summary tables

After any migration into `data.tRecordApiExecution` or `data.tRecordInteractiveApiExecution`,
rebuild the pre-aggregated summary tables used for reporting:

```sql
EXEC perfDashboard.CreateBatchCrudSummary;
EXEC perfDashboard.CreateUserCrudSummary;
```

Both procs TRUNCATE and rebuild from scratch. See `perfDashboard-Summary.md` in the Obsidian vault
for full schema documentation.
