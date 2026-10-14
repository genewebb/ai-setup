---
name: dynamic-tsql-gotchas
description: QUOTENAME-in-concatenation SSMS syntax errors, SQL 2022 log-space column name, TSqlExpressionConverter T.[ alias replacement rule
metadata:
  type: reference
---

Three SQL/T-SQL gotchas learned during speed-merchants SQL work:

1. **QUOTENAME in dynamic T-SQL**: using `QUOTENAME()` inside a multi-line string concatenation for `EXEC()`/`sp_executesql` frequently triggers "Incorrect syntax near 'QUOTENAME'" in SSMS. Safe workaround: build bracket-quoted identifiers manually as `N'[' + REPLACE(@name, N']', N']]') + N']'` stored in a variable before concatenating.
2. **SQL Server 2022 log space**: the column in `sys.dm_db_log_space_usage` is `used_log_space_in_percent` (not `LogSpaceUsedPercent`).
3. **TSqlExpressionConverter** (Profisee `Utilities.Expressions`) emits column references as `T.[ColumnName]`; safe alias replacement must use `Replace("T.[", newAlias + "[")` — never bare `Replace("T.", newAlias)`, which corrupts string literals in the generated T-SQL. `ExpressionsService` demonstrates the safe pattern (`Replace("T.[", "P.[")`).

(Migrated from myworkspace AGENTS.md, 2026-07-30.)
