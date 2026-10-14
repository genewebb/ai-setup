---
name: reference_connex_service_store_and_logs
description: "Where ConnEx persists strategies/configs and where its errors do (and don't) surface; bodyless-500 pattern"
metadata: 
  node_type: memory
  type: reference
  originSessionId: 8b8867b7-b89d-47cf-a33b-b7e810f45b44
---

ConnEx live state + logs live in the SEPARATE **`Profisee`** database (same local server), NOT `speedmerchants`. The `speedmerchants.connex.*` schema is an EMPTY DUPLICATE — always query the `Profisee` DB:
- `Profisee.connex.tIntegrationStrategyConfiguration` — imported strategies (verified: `Export PDATA120 with Connect` Id 7 persisted here on successful import; `speedmerchants.connex` version stays empty and misled the first pass)
- `Profisee.connex.tServiceConfiguration`, `.tServiceProvider`, `.tCredentialsVault`, `.tJob`, `.tBatch`
- `connexjobs.*` (Hangfire) exists in speedmerchants but only runs housekeeping/partition jobs — strategy *import* is SYNCHRONOUS (no Hangfire job). Note the ConnEx credential vault holds ONE shared Username/Password pair reused across all SQL service configs.

**Where ConnEx.Api actually logs: the SEPARATE `Profisee` database's `logging.tSystemLog`** — NOT `speedmerchants.logging.tSystemLog` (that one only has live Gateway.Api rows; ConnEx.Api stopped there 2026-06-28 and is a red herring). Query `Profisee.logging.tSystemLog WHERE AssemblyName='Profisee.Platform.Services.ConnEx.Api'` for the failure window — that's where the ConnEx exception (SQL errors, stack, retries) appears. Both DBs are on the same local server; cross-DB query works from the speedmerchants MCP.

A ConnEx **empty-body HTTP 500** = unhandled server-side exception with no serialized payload; TestAuto's `ConnExExecutor` correctly appends the response body (ConnExExecutor.cs:496-511), so a blank `errorDetail` in "Request failed with HTTP 500. Expected one of... . " just proves the body was empty — look in `Profisee.logging.tSystemLog`, not the TestAuto code.

**Diagnostic signature — ConnEx export/import 500 caused by target-DB login:** ConnEx connects to the target SQL DB using the service config's vault username; if that login can't open the DB (SQL Error 4060, "Cannot open database … Login failed for user 'X'") ConnEx **retries 8× with exponential backoff (1→2→4→8→16→32→64→128s ≈ 100s+)** then throws while introspecting schema (`SELECT … FROM sys.objects`) → bodyless 500. Root cause is almost always the vault login lacking a **database-user mapping** in the target DB (login exists+enabled at server level but no user in the DB). Fix = `CREATE USER … FOR LOGIN` + datareader/datawriter (+ddladmin if ConnEx manages the target table). Seen 2026-07-01: login `ConnectWrite` unmapped in `ConnectExport` broke exec 10000172 step 4. See [[reference_profisee_platform_log]], [[reference_hangfire_job_exception]].
