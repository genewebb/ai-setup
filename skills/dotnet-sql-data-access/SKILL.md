---
name: dotnet-sql-data-access
description: >
  ADO.NET SQL data access patterns used in the speed-merchants TestAuto project. Use when writing
  or reviewing SQL queries, SqlParameter construction, SqlHelper usage, SqlBulkCopy bulk operations,
  keyset pagination, direct SqlConnection/SqlCommand patterns, or diagnosing why EF is absent.
---

# ADO.NET SQL Data Access Patterns

This codebase uses `Microsoft.Data.SqlClient` directly — Entity Framework is banned. The primary
wrapper is `SqlHelper` from `Profisee.Platform.Utilities.DataAccess`, which handles connection
open/close per call. Direct `SqlConnection`/`SqlCommand` is used only when `SqlHelper` cannot
satisfy a requirement (e.g. `InfoMessage` events, infinite command timeout, multi-batch transactions).

## When to Use

- "Writing a new repository that queries a SQL Server database"
- "Adding SqlParameter to a query"
- "Using SqlBulkCopy to insert many rows"
- "Implementing keyset pagination against a large table"
- "Deciding whether to use SqlHelper or direct SqlConnection"
- "Diagnosing a transient SQL error with retry logic"

## Connection and Command Pattern

### Standard: SqlHelper (preferred)

`SqlHelper` is the default for simple queries. It opens and closes its own connection per call.
Instantiate with a connection string and dispose with `using`.

```csharp
using var sqlHelper = new SqlHelper(_connectionString);

// Execute a reader
using var reader = sqlHelper.ExecuteDataReader(sql, parameters.ToArray());
while (reader.Read())
{
    var value = reader.IsDBNull(0) ? null : reader.GetValue(0);
}

// Execute a scalar
var result = sqlHelper.ExecuteScalar(sql, parameters.ToArray());
return Convert.ToInt64(result ?? 0);
```

Run inside `Task.Run(...)` to avoid blocking async callers:

```csharp
return await Task.Run(() =>
{
    using var sqlHelper = new SqlHelper(_connectionString);
    using var reader = sqlHelper.ExecuteDataReader(sql, parameters.ToArray());
    // ...
}, cancellationToken);
```

### Exception: Direct SqlConnection

Use `SqlConnection`/`SqlCommand` directly only when `SqlHelper` cannot satisfy the requirement.
The three documented reasons (from `SqlScriptExecutor`) are:

1. `InfoMessage` event needed for real-time `PRINT`/`RAISERROR WITH NOWAIT` streaming
2. Per-command timeout override (`CommandTimeout = 0` for infinite)
3. Multi-batch transaction management across N GO-delimited batches

```csharp
// Direct connection — wires InfoMessage for real-time progress
var builder = new SqlConnectionStringBuilder(connectionString);
builder.CommandTimeout = sqlStep.SqlCommandTimeoutSeconds; // 0 = infinite

var connection = new SqlConnection(builder.ConnectionString);
connection.InfoMessage += (_, e) =>
    _logger.InformationWithTag(LogTagConstants.SqlScript, "[SQL {Role}] {Message}", role, e.Message);

await connection.OpenAsync(cancellationToken);

using var command = new SqlCommand(batchText, connection, transaction)
{
    CommandType = CommandType.Text,
    CommandTimeout = sqlStep.SqlCommandTimeoutSeconds
};
return await command.ExecuteNonQueryAsync(cancellationToken);
```

Simple direct pattern (no `SqlHelper`, no `InfoMessage`):

```csharp
await using var conn = new SqlConnection(_settings.ConnectionString);
await conn.OpenAsync(ct);

await using var cmd = conn.CreateCommand();
cmd.CommandText = sql;
cmd.CommandTimeout = 60;
cmd.Parameters.AddWithValue("@BatchSize", batchSize);
cmd.Parameters.AddWithValue("@LastCode", lastCode ?? "");

await using var reader = await cmd.ExecuteReaderAsync(ct);
while (await reader.ReadAsync(ct)) { ... }
```

## Query Builder Methods

`RecordPoolRepository` centralises SQL construction in two private builder methods:

```csharp
// SELECT TOP with keyset and optional exclude-list
private (string Sql, List<SqlParameter> Parameters) BuildSelectQuery(
    string tableName,
    RecordPoolSourceSystem sourceSystem,
    int count,
    string? startingCode,
    IEnumerable<string>? excludeCodes)

// SELECT TOP filtered to a specific IN-list of codes
private (string Sql, List<SqlParameter> Parameters) BuildSelectQueryWithCodes(
    string tableName,
    RecordPoolSourceSystem sourceSystem,
    int count,
    IEnumerable<string> codes)
```

Both return a `(string Sql, List<SqlParameter> Parameters)` tuple that is passed directly to
`ExecuteQueryAsync`. This keeps SQL construction testable and separate from execution.

## SqlParameter Usage

### Typed parameters (preferred for production queries)

Specify `SqlDbType` and length explicitly to prevent parameter-sniffing issues:

```csharp
var parameters = new List<SqlParameter>
{
    new SqlParameter("@Count", SqlDbType.Int) { Value = count },
    new SqlParameter("@LastCode", SqlDbType.NVarChar, 100) { Value = lastCode },
    new SqlParameter("@SourceSystem", SqlDbType.NVarChar, 10) { Value = sourceSystemCode }
};
```

### Dynamic IN-list parameters

Never concatenate user values into SQL. Generate one `@paramN` per value:

```csharp
var paramNames = excludeList.Take(1000).Select((c, i) =>
{
    var name = $"@ex{i}";
    parameters.Add(new SqlParameter(name, c));
    return name;
});
whereClause.Add($"[Code] NOT IN ({string.Join(", ", paramNames)})");
```

Same pattern for `BuildSelectQueryWithCodes`:

```csharp
var codeParamNames = codeList.Select((c, i) =>
{
    var name = $"@code{i}";
    parameters.Add(new SqlParameter(name, c));
    return name;
});
whereClause.Add($"[Code] IN ({string.Join(", ", codeParamNames)})");
```

### AddWithValue (simple / internal queries)

`cmd.Parameters.AddWithValue("@Name", value)` is acceptable for internal tooling where
type inference from the .NET value is adequate.

## Keyset Pagination

Use `TOP (@Count)` + `WHERE [Code] > @LastCode ORDER BY [Code]` — not `OFFSET/FETCH` — for
high-performance pagination over large tables. The query hint `OPTION (OPTIMIZE FOR UNKNOWN, MAXDOP 4)`
prevents parameter sniffing on large tables:

```csharp
var sql = $@"
    SELECT TOP (@Count) {columns}
    FROM {tableName}
    {whereClause}
    ORDER BY [Code]
    OPTION (OPTIMIZE FOR UNKNOWN, MAXDOP 4)";
```

One-time `OFFSET/FETCH` is used only to locate the starting cursor for a given row position:

```csharp
var sql = $@"
    SELECT [Code]
    FROM {tableName}
    {whereClause}
    ORDER BY [Code]
    OFFSET @RowPosition ROWS
    FETCH NEXT 1 ROW ONLY";
```

## Bulk Operations

`BulkCopyHelper` in `TestData.Shared` provides two overloads of `BulkCopyAsync<T>`:

```csharp
// Opens its own connection
await BulkCopyHelper.BulkCopyAsync(
    items,
    destinationTable: "dbo.RetailClientCloned",
    connectionString: connStr,
    batchSize: 5000,
    columnMappings: null,   // null = auto-map by DataColumn name
    cancellationToken: ct);

// Reuses an open connection (required for staging into a temp table)
await BulkCopyHelper.BulkCopyAsync(
    connection,
    items,
    destinationTable: "#StagingTable",
    batchSize: 5000,
    cancellationToken: ct);
```

Internally both overloads call `items.ToDataTable(columnMappings)` (an extension method) to
produce the `DataTable`, then map `DataColumn` names 1:1:

```csharp
foreach (DataColumn col in dataTable.Columns)
    bulk.ColumnMappings.Add(col.ColumnName, col.ColumnName);

await bulk.WriteToServerAsync(dataTable, cancellationToken);
```

Direct `SqlBulkCopy` usage (without the helper) follows the same pattern — build a `DataTable`
via reflection, map columns, call `WriteToServerAsync`.

## Transient Error Retry

`RecordPoolRepository.GetRecordsByKeysetAsync` retries up to 3 times on transient SQL errors
with exponential backoff:

```csharp
private static bool IsTransientError(Exception ex)
{
    if (ex is SqlException sqlEx)
    {
        return sqlEx.Number == -2    // Timeout
            || sqlEx.Number == 10054 // Connection forcibly closed
            || sqlEx.Number == 10053 // Connection aborted
            || sqlEx.Number == 233   // Connection does not exist
            || sqlEx.Number == 64    // Host unreachable
            || sqlEx.Number == -1;   // Connection error
    }
    if (ex is InvalidOperationException && ex.Message.Contains("Internal connection fatal error"))
        return true;
    return false;
}

// Exponential backoff: 2s, 4s, 8s
var delay = TimeSpan.FromSeconds(Math.Pow(2, retryCount));
await Task.Delay(delay, cancellationToken);
```

## SqlIdentifierValidator

Table and schema names that come from configuration are validated with `SqlIdentifierValidator`
before being interpolated into SQL to prevent injection via config values:

```csharp
SqlIdentifierValidator.ValidateIdentifier(logicalName, nameof(logicalName));
var physicalTable = $"data.[t{logicalName}]";

// Also used in TRUNCATE:
cmd.CommandText = $"TRUNCATE TABLE [{SqlIdentifierValidator.ValidateIdentifier(
    _settings.CloneDestinationTable, nameof(_settings.CloneDestinationTable))}];";
```

Validated table names are safe to interpolate. User-supplied values always go through `SqlParameter`.

## Examples

```csharp
// RecordPoolRepository: keyset query with typed parameters
var parameters = new List<SqlParameter>
{
    new SqlParameter("@Count", SqlDbType.Int) { Value = count }
};

if (!string.IsNullOrEmpty(lastCode))
    parameters.Add(new SqlParameter("@LastCode", SqlDbType.NVarChar, 100) { Value = lastCode });

if (sourceSystem.RequiresSourceSystemFilter)
    parameters.Add(new SqlParameter("@SourceSystem", SqlDbType.NVarChar, 10) { Value = sourceSystemCode });

return await Task.Run(() =>
{
    using var sqlHelper = new SqlHelper(_connectionString);
    using var reader = sqlHelper.ExecuteDataReader(sql, parameters.ToArray());

    var result = new List<Record>();
    while (reader.Read())
        result.Add(MapReaderToRecord(reader));

    return result;
}, cancellationToken);
```

```csharp
// MatchingActivityMonitorService: passing inline params to SqlHelper
using var sqlHelper = new SqlHelper(_connectionString);
using var reader = sqlHelper.ExecuteDataReader(
    sql,
    new SqlParameter("@StrategyName", SqlDbType.NVarChar, 255) { Value = strategyName },
    new SqlParameter("@LookbackMinutes", SqlDbType.Int) { Value = lookbackMinutes });
```

## Sources

- `TestAuto.Matching/Services/RecordPoolRepository.cs`
- `TestAuto.Matching/Services/MatchingActivityMonitorService.cs`
- `TestAuto.Matching/Helpers/MatchingMetricsCollector.cs`
- `TestData.Shared/Helpers/BulkCopyHelper.cs`
- `TestData.CloneAndMutate/Repository/RetailClientRepository.cs`
- `TestAuto.Utilities/Executors/SqlScriptExecutor.cs`
