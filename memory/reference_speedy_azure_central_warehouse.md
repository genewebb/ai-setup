---
name: reference_speedy_azure_central_warehouse
description: "The real Azure SQL central warehouse for vNext Speedy — server/database/login (SpeedyAdmin, verified connecting), where the credential is stored, and what is already provisioned in it"
metadata: 
  node_type: memory
  type: reference
  originSessionId: 25a6f180-ace3-4c16-9718-60b837d6c54c
  modified: 2026-09-09T02:58:30.645Z
---

Gene provisioned the real central warehouse 2026-09-08 10:05 and said to use it for the rest of vNext
development. It is the "central" half of [[project_vnext_two_stores_install_gate]]; the local warehouse
stays the compose container on port 14400.

- Server `wus2-pc-profisee-sqlserver-0.database.windows.net`, database `pc-speedy-dw`, admin `ProfiseeAdmin`.
- **The credential is NOT in this file and must never be.** It lives in the user environment variable
  `SPEEDY_CENTRAL_CONNECTION` (full connection string) and in the settings file
  `C:\devopslocal\Secrets\speedy-central.settings.json`, which `speedy migrate --settings <path>` reads.
  Both are outside every repo. Gene will rotate the password when development ends.
- Read it with `[Environment]::GetEnvironmentVariable('SPEEDY_CENTRAL_CONNECTION','User')` — a plain
  `$env:` read misses it in a shell that started before it was set.
- Use `Encrypt=True;TrustServerCertificate=False`. Against Azure, `TrustServerCertificate=True` defeats the
  point of the encrypted channel.

**The login is `SpeedyAdmin`, NOT `ProfiseeAdmin`.** `ProfiseeAdmin` is refused with 18456 on every form —
it is the Entra admin Gene signs into SSMS with interactively, and that password was never a SQL login
password. Gene created a **contained database user** in `pc-speedy-dw` on 2026-09-08 10:20
(`CREATE USER [SpeedyAdmin] WITH PASSWORD = ...` then `ALTER ROLE [db_owner] ADD MEMBER`), same password.
Verified working: connects in ~1 s, `IS_ROLEMEMBER('db_owner')` = 1.

**A contained user cannot reach `master`, and that breaks `migrate`.** `migrate --check` works (it reported
the 14 declared objects absent, correctly). The full `migrate` fails at the first pass, because
`WarehouseMigrator.cs:43-44`, `:77` open `master` first — `CREATE DATABASE` cannot run from inside the
database it creates — and a contained user has no principal there. **Gene 2026-09-08 10:22: "we can assume
it exists going forward"** — the central catalog is provisioned by the platform, never by this tool. Row
**59.3f** carries the fix: try the target catalog first and skip the `master` hop when it opens, falling
back only on 4060.

**RE-VERIFIED 2026-09-08 22:58, before the 48.x publication block was dispatched, and it is fully live** —
`SpeedyAdmin` opened in **842 ms**, `SUSER_SNAME()` = `SpeedyAdmin`, `Microsoft SQL Azure (RTM) 12.0.2000.8`.
There is nothing left open about the login; treat the 18456 as closed and only `ProfiseeAdmin` as refused.
What is already provisioned, which is the operand 48.F's completeness census needs:

- **11 tables** — `dbo.AgentHeartbeat`, `AgentPresence`, `CapturedRunProfile`, `DesiredState`,
  `ExpectedDriver`, `LoadWorkloadRun`, `Metric`, `Run`, `RunProfile`, `RunRampStep`, `WorkItem`
- **5 `bi.` views** — `DimAgent`, `DimRun`, `DimRunEnding`, `FactMetricSample`, `FactRunMeasures`

So the migration has been applied here at least once, and 48.F is a completeness delta rather than a first
run. Probe it with `C:\temp\probe-central.ps1` (prints server/database/login and the object inventory, never
the password).

Only the coordinator ever opens this connection (`StateProgression` is registered solely by
`CoordinatorModule`, and `src/Agent` does not reference `src/Coordinator`), so Azure needs ONE firewall
entry, not one per agent box. Options and their trade-offs are written up in
`Q:\Work\Work\99 Documentation\speed-merchants\vNext\Design\CentralConnectivity_Azure.md`.
