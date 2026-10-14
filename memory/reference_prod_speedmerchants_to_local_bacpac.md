---
name: reference-prod-speedmerchants-to-local-bacpac
description: "Pulling prod speedmerchants (Azure Hyperscale) to local SQL 2022 via BACPAC - script on D:, and the 6 traps hit on 2026-10-07"
metadata:
  node_type: memory
  type: reference
  originSessionId: 3e39a981-ec2a-4aac-b6e4-21982d684786
  modified: 2026-10-08T02:42:00.349Z
---

Script: `D:\PowershellScripts\Restore-ProdSpeedmerchantsLocal.ps1` (Copy -> Clean -> Export -> Import to a NEW local name, default speedmerchants_prod_<yyyyMMdd>; creds inline at top by Gene's choice, personal share). Prod = `pc-speedmr-prd-db` on wus2-pc-profisee-sqlserver-0, Hyperscale, pool `pc-prd-elasticpool-0`; login ProfiseeAdmin (server admin, dbo everywhere). Creds file `C:\Tmp\pc-speedmr-prd-db.json` (system/userid/password).

Traps (all fixed in the script):
- SqlPackage 170.1.61 Import emits `ADD PERIOD FOR SYSTEM_TIME ($ValidFromDTM, ...)` unbracketed -> Msg 102 after 12 min of data load. 170.5.96 works. `dotnet tool update` needs `--add-source https://api.nuget.org/v3/index.json --ignore-failed-sources` (hangfire feed 401s).
- Export fails SQL71501 on 11 dead views/functions (24R1, ResultsBeginToEnd, perfDashboard.vMatchingRuns...) whose tables are gone in prod; drop them in the COPY.
- Contained users + Entra principals block import into local -> drop all users in the copy.
- Fresh Azure copy says ONLINE ~30-60s before it accepts logins ("Login failed").
- From Azure master, `DB_ID('otherdb')` is NULL -> `IF DB_ID(..) DROP` silently no-ops; use sys.databases.
- PowerShell `@"..."@` expands `$24R1_...` in SQL; use `@'...'@`. Table vars take tempdb collation -> Msg 451 vs catalog names.

Replacing local [speedmerchants] needs Profisee 26.2 service + 19 `speedmerchants*` IIS pools stopped (they win deadlocks vs SINGLE_USER), then Profisee Configuration Manager (Gene runs it). See [[project-local-two-profisee-installs-required]].
