---
name: reference_warehouse_loopback_127_not_localhost
description: "speedmerchants compose warehouse on the host: use 127.0.0.1,14400, never localhost,14400 (resolves ::1 first, listener IPv4-only, client times out); a \"Skipped\" live test is NOT a pass"
metadata: 
  node_type: memory
  type: reference
  originSessionId: 22d5dbd3-c155-4749-bee7-fcbb38ec1329
  modified: 2026-09-14T01:46:29.341Z
---

The compose `warehouse` SQL Server publishes on loopback only at `127.0.0.1:14400` (IPv4). On CORPLTR94 `localhost` resolves to `::1` first; a connect to `::1,14400` is refused (~2 s) and both sqlcmd and Microsoft.Data.SqlClient time out on `Server=localhost,14400`. `Server=127.0.0.1,14400` connects instantly.

**Why it bit:** 52.S0.3a's grader clause H14 built `localhost,14400`; a pre-dispatch "route check" ran the SaturationSeries live tests and printed `Passed 22, Skipped 2` — the 2 skipped WERE the live tests, and the lead read it as the route working. The worker caught it.

**How to apply:**
- Any live-SQL test, grader or probe from the host: `SM_TRANSPORT_CONNECTION = "Server=127.0.0.1,14400;Database=master;User Id=sa;Password=$env:SM_SA_PASSWORD;TrustServerCertificate=True"` (never print it). Containers use `warehouse,1433`.
- When proving a live route, filter to the live test class and require `Skipped: 0`; a skip is "not proven".
- Live tests use scratch catalogs (`SaturationSeriesTests` LiveTransport pattern), never `SpeedmerchantsWarehouse`.

Related: [[project_myfable_foreman]], [[feedback_verify_no_guessing]].
