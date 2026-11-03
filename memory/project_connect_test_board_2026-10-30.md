---
name: project_connect_test_board_2026-10-30
description: "Connect test board (SMVMTR1 Status.html from C:\\tmp\\connect-status\\ConnectTestBoard.html via build-status.sh) + 11/02 shared/1k/1m CrewChief layout, per-size baselines, TestAuto workflow codes; network-blocked connectors go last"
metadata:
  node_type: memory
  type: project
  originSessionId: 4dd36d8c-694d-4696-be28-10c24d7ba30b
  modified: 2026-11-03T04:12:58.615Z
---

Connect throughput test (SMVMTR1 CrewChief + PROD TestAuto, 26R3) has a status page, started 2026-10-30:
- Artifact: https://claude.ai/artifact/Mw4tDbZNeXUgVRWAAJXdgQ
- Source: C:\tmp\connect-status\ConnectTestBoard.html. All state lives in the `BOARD` JS object at the bottom (connectors, runs per Export/Import x 1K/1M, setup steps, open items). Edit data only, republish the same file path.
- Grid: 5 connectors x 2 directions x 2 sizes = 20 runs. Passed = prepare OK, workflow OK, row count right, metrics collected.
- State at start: setup steps 1-5 done 10/15; Step 6 (portal Strategy SQL Server Export + connect-database-backup) waiting on Gene; Databricks/Synapse/P2P exports ready.

Run notes: c:\tmp\FullConnectTest.md, c:\tmp\restartconnect.md (the vault note 99_Frequent\Connect.md is from 10/14 and stale).

**Gene 10/30 rule:** a connector with network access problems (Snowflake, 390422) goes to the BOTTOM of the run order as Parked; come back to it later. Primary goal = get through all testing.
**How to apply:** republish the board whenever a test step result comes in. Never block other connectors on a parked one. No key-exposure warnings ([[feedback_test_keys_no_warnings]]).

**SMVMTR1 copy (10/30):** plain folder `C:\inetpub\wwwroot\ConnectTesting\` (Status.html + web.config: default doc Status.html, cache disabled), same pattern as the stream page `wwwroot\speedy\status.html`; NO IIS app, no admin step. URL https://smvmtr1.corp.profisee.com/ConnectTesting/Status.html (200 from laptop 10/30). Status.html = ConnectTestBoard.html wrapped in doctype/head/body. Every board update: republish artifact AND rebuild + copy Status.html to `\SMVMTR1\c$\inetpub\wwwroot\ConnectTesting\` (SMB write from laptop works).

Update SMVMTR1 copy after editing the board: `sh /c/tmp/connect-status/build-status.sh` (wraps, copies, prints HTTP status).

**Naming rule (Gene 10/30):** a Profisee entity that RECEIVES data = *Import (incl. the SMVM2 target of the P2P EXPORT); a non-Profisee table an export writes = *Export. Renamed in New-ConnectWorkloads.ps1: PDataProfiseeExport -> PDataSourceImport (SMVM1 export source, loaded from ModelSource), PDataProfiseeToProfiseeExport -> PDataProfiseeToProfiseeImport (SMVM2). `$RetiredEntity`/`$RetiredTargetEntity` lists make the entity resets delete the old names. Deployed to SMVMTR1 19:40 (backup backup-connect-workloads-20261030-naming). Needs: bootstrap rerun, portal Strategy SQL Server Export rebuilt on PDataSourceImport, backup, testauto-setup.
Regen recipe: copy SMVMTR1 data\workloads\connect + folders + reference-kv to scratch, QA folder from \SMVMTR1\c$\Deploy\CrewChief\backup-workloads-20261015-noncconnect\workloads\cz-perf-tests, run generator -Environment SMVMTR1 -DataFolder <scratch> -QaFolder <qa>, `diff -rq --strip-trailing-cr`. DEPLOY EVERY file the diff lists (10/30: deployed 4 of 15, bootstrap 404 "Entity PDataProfiseeExport cannot be found" from stale connect-strategies-create); after copy re-diff must be empty.

10/30 20:00-20:55: rebuild done via CLI runner ([[reference_crewchief_cli_runner_smvmtr1]]). SMVM2 had LOST the 50 Dba_*_PDATA domains (generator assumed present): ran connect-model-profisee-to-profisee-target-domains-create (50 x 30 records), then P2P bootstrap passed. Strategy SQL Server Export is now TEMPLATE-built (templates\sql-server-export.json = synapse-export with databaseType SqlServer; generator $stratSpec.SqlServerExport, $portalBuilt now only ProfiseeToProfiseeImport). Backup 20:50 profisee_ConnectBaseline.bak. Remaining portal step: Strategy Profisee To Profisee Import (asked Gene 20:25), then rerun backup.

**10/31 05:22-05:43:** SQL Server Export 1K PASSED: batch 23 Succeeded, 1000 rows in ConnectExport.dbo.PDataSqlServerExport, prod metric row (tConnectApiExecution) DatabaseExport 1000 recs 3504 ms. Import prepare first FAILED: gateway DELETE v1/Records/bulk/{entity} answers **HTTP 202** (async). Fix in New-ConnectWorkloads.ps1: Empty steps accept 202 + new `New-WaitEmptyStep` SQL poll (data.t{{EntityName}} empty, 30 min, P2P uses $TargetIntegratedConnection); New-SqlStep gained -CommandTimeoutSeconds. 6 prepares deployed (backup backup-connect-workloads-20261031-202wait), IN-SYNC. Import prepare passed 05:42; waiting on Gene: TestAuto Connect SQL Server Import (run profile 26R3-SQLSERVER-PROFISEE-I-1000-1000-0-4). Reset restores baseline, so connex.tBatch max = 21 after it.

**11/02 LAYOUT (supersedes the run-settings size switch below):** CrewChief connect workloads = `connect\shared` (size-free; generator THROWS if one declares SourceTableName/RecordCount, since a child global beats the parent) + `connect\1k` / `connect\1m` (thin parents setting the size: `connect-<size>-<provider>-<export|import>`, `-database-reset/-backup`, `connect-1m-database-baseline-create`, `-<provider>-credentials-refresh`, `-testauto-setup`). Parent globals DO reach children incl. inside child globals (probe 11/02). `connect-run-settings.json` holds only WorkerThreadCount. Baselines per size: E:\SQLBackups\profisee_ConnectBaseline_PDATA1K/_PDATA1M.bak; reset fails fast if 'Strategy Source Data Load' reads the wrong table. TestAuto workflows per size: 1K = 10000198-10000207 (renamed, codes kept), 1M = 10000218-10000225; P2P 1K only. Runner: scratchpad 4dd36d8c… `run-size.sh <1k|1m> <provider> <export|import> <code>`, `connectivity.sh <snowflake|synapse> [refresh]`. A .bak copied over SMB lacks NT SERVICE\MSSQLSERVER, so SQL backup over it fails with OS error 5; grant it. Synapse 1K passed 11/02 (metrics 16024/16025); Snowflake moving to a NEW environment (key pair), waiting on values.

**11/02 evening: THREADS dimension (4/8/12).**
- `WorkerThreadCount` is a parent global like size: the shared prepares must not declare it, and `connect-run-settings`
  is RETIRED (removed).
- Thread parents live in `connect\<size>\t8|t12\connect-<size>-t8|t12-<provider>-<dir>`; 4 threads keeps the plain names.
- TestAuto:
  - 54 run profiles: 4T IDs 8-26 + 45, 8T/12T IDs 27-44 and 46-63.
  - 54 workflows (10000198-10000262), names "… 1M 8T"; the collect-step profile check passed 54/54.
- 1M at 4 threads all passed 11/02:
  - SQL Server: E 7m, I 10m.
  - Databricks: E 50m, I 16m.
  - Synapse: E 2h27m, slowing; I 45m.
  - P2P: E 13m (workflow 10000226).
- CLI runner gotcha:
  - `Run-Queued.ps1`'s final Set-Content of `status.json` can fail when `run-cc.sh` polls it over SMB, leaving
    "Running" behind.
  - `run-cc.sh` now falls back to the log's `Outcome:` line, and `run-size.sh` retries on BUSY.
  - A proper fix in `Run-Queued.ps1` (temp file + Move retry) was denied by the classifier and awaits Gene.

**10/31 12:28:** Board = SMVMTR1 HTML ONLY (Gene: artifact not tied to an account; artifact Mw4tDbZNeXUgVRWAAJXdgQ deleted). Edit C:\tmp\connect-status\ConnectTestBoard.html + build-status.sh. TestAuto workflows now run by Claude via POST :8443/api/workflows/{code}/execute (ta-run.sh). Passed 1K: SQL Server E+I, Databricks E+I, P2P E. Synapse BLOCKED: Azure AD client secret expired (AADSTS7000222). P2P moved above Synapse (Gene). P2P import waits on Gene portal strategy; plan: export it to a template after, since connect-profisee-to-profisee-connect-setup deletes/recreates the P2P service configuration.
**10/31 12:41:** P2P IMPORT DOES NOT EXIST: portal "Add New Integration Strategy" with Service Configuration Profisee To Profisee offers only the Export flow. P2P = export only (passed 1K). Board marks Import n/a. Generator still emits connect-profisee-to-profisee-import-prepare + TestAuto workflow 10000204 (unused; candidate cleanup, ask Gene). Next: Synapse secret (Local Secrets 'Synapse SQL Database Service Provider':DbPassword), AADSTS7000222.
**10/31 13:05:** P2P import cleanup DONE: generator ($Entity/$Strategy/$Run/$portalBuilt, $RetiredEntity += PDataProfiseeToProfiseeImport on Main, $RetiredWorkflow/$RetiredRunProfile delete steps in testauto workloads, retired prepare file), deployed IN-SYNC (backup backup-connect-workloads-20261031-p2pimport), testauto-setup deleted workflow 10000204 + run profile, bootstrap + NEW baseline backup 12:5x. Snowflake: SMVMTR1 (egress 52.167.58.22) now reaches it; Connect on SMVM1 (egress 52.167.58.31) fails strategy import 400 "Unable to access database server" -> likely network policy (unconfirmed). Synapse creds Monday 11/2.
