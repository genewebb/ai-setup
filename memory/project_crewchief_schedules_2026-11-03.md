---
name: project_crewchief_schedules_2026-11-03
description: "11/03 decisions: CrewChief Schedules feature (Windows Scheduled Task) + RunTestAutoWorkflow step; connect folder layout providers/<p>/<size>/t4|t8|t12; cli-wrap obsolete"
metadata:
  node_type: memory
  type: project
  originSessionId: 4dd36d8c-694d-4696-be28-10c24d7ba30b
  modified: 2026-11-03T21:33:15.182Z
---

Decided 2026-11-03 with Gene (Connect throughput testing context, see [[project_connect_test_board_2026-10-30]]):

- **SUPERSEDED 11/03 14:51 by Gene: a schedule is just a CrewChief WORKLOAD** (no new Schedules feature). Its
  global params hold the schedule (task name, date/time, recurrence, target workload); a PowerShell step creates or
  updates the Windows Scheduled Task, which runs `crewchief run workload <target>` from the command line. Restore
  does nothing until someone runs the setup workload. Why a workload: it will migrate to Speedy, and Windows and
  Linux schedulers differ, so only the one PowerShell step gets swapped for Linux (keep parameters OS-neutral). Run-as
  account = a global parameter of the schedule workload (Gene 11/03). NEW STEP TYPE (not a PowerShell step):
  Schedule step, actions Apply (create-or-update) / Delete / Enable / Disable; OS backend inside the executor
  (Windows Task Scheduler now, Linux later). Overlap: Gene chose run in parallel (no run lock). Older idea kept below for history:
- ~~Schedules = a CrewChief feature~~ (UI + CLI): name, ordered workload list, start date/time, daily/weekly recurrence,
  end date, run-as, enabled, notify. Saving creates/updates a Windows Scheduled Task running
  `crewchief run schedule <name>`; history in runs.json. Must be single-instance + CLI data-folder lock (11/03 two
  runners collided on one Profisee DB).
- **New step `RunTestAutoWorkflow`**: POST TestAuto `/api/workflows/{code}/execute`, poll
  `/api/workflows/executions/{code}` to Complete/Failed with timeout; timeout optionally INFINITE (matching runs for days/weeks), reuse the existing
  waitIndefinitely convention. Overlapping scheduled runs are allowed on purpose, no warning. Makes one workload = one whole measured run.
- Build order: step first, then Schedules, then generator changes.
- **Connect workload folder layout (agreed, NOT yet built)**: `connect\shared` (truly shared only), `connect\providers\<p>\`
  (everything provider-specific: prepare, strategies, service config, credentials) then `<size>\t4|t8|t12` for runs;
  `connect\1k|1m` for cross-provider size items (reset, backup, bootstrap, testauto) with t4/t8/t12 prepare-alls.
  Names unchanged unless Gene decides on `-t4`.
- **CLI gap fixed**: CrewChief 8.0.2 runs `run workload <name>` without the cli-wrap `!` (commit e4ff395b, verified
  11/03 13:57). `workloads\cli-runner` + `!` are obsolete; clean up when the generator changes.
- `GET /api/version` (http :5030 on SMVMTR1) + `crewchief version` added (commit 8a2c6655).

- **Portability (11/03 brainstorm)**: QA restores a CrewChief backup with their own secrets file and picks/edits
  schedules (dates, times, order). One schedule per provider per size. Apply = create the Windows task if missing,
  update it if present. Schedules must travel in backup/restore. Also used on the **performance test servers**,
  so Schedules is a generic CrewChief feature, not Connect-only.

- **BUILT 11/03 (uncommitted, branch bug/schedule_cli_updates/genewebb)**: TestAutoWorkflowStep (executionCode attach,
  waitIndefinitely, maxConsecutivePollFailures) + ScheduleTaskStep (IScheduledTaskBackend, WindowsTaskSchedulerBackend =
  Task Scheduler COM, folder \CrewChief\). Unit 4442 green; real Task Scheduler integration test passes (elevated).
  Gotchas: dynamic COM throws FileNotFoundException (check HResult 0x80070002), and XML LogonType "ServiceAccount" is
  rejected (0x80041318), so SYSTEM tasks omit LogonType. Re-attach after reboot = CrewChief marker per TestAuto URL+workflow in <data>/testauto-active-runs (TestAuto executions have no template link, so no TestAuto endpoint possible without a model change; Gene chose marker). Apply re-enables a disabled task (Gene). Design: Q:\Work\Work\99 Documentation\speed-merchants\planning\2026-11-03-crewchief-testauto-and-schedule-steps-design.md.
- **8.1.0 deployed 11/03 15:51 (commit e0d373de).** Then 16:00-16:40 (uncommitted): `waitOnly` on TestAutoWorkflowStep
  (guard first in each `-run`: a -run resets the DB before its TestAuto step, so plain re-attach can't protect an
  in-flight run). 8.1.0 IGNORES waitOnly and would START the run, so CrewChief with waitOnly must deploy BEFORE the
  -run workloads. Generator reorg built (Get-LayoutFolder, providers\<p>\<size>\t4|t8|t12, names unchanged) + 54 -run,
  10 -all, 10 schedule-connect-<size>-<p>; staged in scratchpad regen8, not deployed. Workflow codes = PROD repo's
  (Gene). Run-as = CORP\speedmerchants (verified via SID of the CLI Runner task) + secret Scheduler:RunAsPassword (Gene adds).

**Why:** Gene wants daily/weekly unattended Connect runs owned by CrewChief, not bash on the laptop.
**How to apply:** design new work against this; speed-merchants = no commits by Claude (git-guard), Gene commits.
- 11/03 ~17:00: Gene chose guard = wait on ANY run: waitOnly + blank workflowCode waits for every marker at the TestAuto (new ITestAutoActiveRunStore.FindAll). -run guards now blank. Schedule defaults stay Sat 02:00 with an overlap warning in notes. Unit 4456 green; regen8 rebuilt, 831 steps deserialize clean.
- 11/03 16:49 CrewChief 8.1.1 deployed (commit 0ec01a1b, waitOnly + FindAll; web + CLI verified). 17:00 reorg DEPLOYED to SMVMTR1 (Gene: now, adds before deletes): backup \\SMVMTR1\c$\Deploy\CrewChief\backup-connect-20261103-reorg; 158 copied, 84 old copies + 3 empty dirs removed, catalogue replaced; live = staged (194 files, 0 mismatch); no shadows. Secret Scheduler:RunAsPassword added by Gene. Test Apply schedule-connect-1k-sql-server OK (task \CrewChief\schedule-connect-1k-sql-server, CORP\speedmerchants, Sat 02:00, target connect-1k-sql-server-all) then DISABLED via schtasks. Re-running Apply re-enables it. cli-runner still in use by tonight's round; remove after with Gene's OK.
- 11/03 19:40 (Gene): schedule workloads moved to connect\schedule\1k|1m\schedule-connect-<size>-<provider> (generator Get-LayoutFolder + keep-list + checks; backup .bak-20261103-schedulefolder). Deployed: 10 moved, live = staged (194, 0 mismatch), catalogue has connect/schedule, /1k, /1m. Windows task \CrewChief\schedule-connect-1k-sql-server unaffected (it runs the -all by name).
- 11/03 20:30 (Gene) 26R2 on SMVMTR2: generator Environment SMVMTR2. Rules: 26R2 Main has Windows service 'Profisee 26.2.0 (<instance>)', stop it BEFORE IIS stop/recycle/restore and start AFTER IIS (26R3+ none; nothing older than 26R2 tested). TestAuto workflows keep identical names across versions; version + Main machine are TAGS (26R3,SMVM1 / 26R2,SMVM2), no version in Description; identity = name + exact tags; only TR1 adopts untagged ones. Two passes: TR2 -run/-all/schedule only after its PROD workflow codes exist. Never run TR1 and TR2 connect tests at once (shared remote targets). Details in C:\tmp\ConnectTestingInProgress.md.
- TODO (Gene 11/03): Connect source should use ONLY ModelSource.dbo.PDATA, size = which ModelSource<size> DB is restored (see [[project_modelsource_split_per_size_dbs_2026-10-28]]); today SourceTableName PDATA1K/PDATA1M copies exist on SMVMDB1 + SMVMDB2. Do for both versions after the 26R2 runs.
- 11/03 21:35: SQL logins for Connect SQL service configs = standard SQL admin ProfAdmin via {{$config:UserCredentials:SqlAdminUser}} / SqlAdminPassword (Gene: standard on all our machines). CLI Runner now also on SMVMTR2 (TODO SMVMTR3). TR2 26R2 workflow codes 10000263-10000316.
- 11/03 22:20 (Gene): ORDER = finish EVERY 26R3 test (incl 1K 8T/12T + Snowflake 1M), then 26R2; flag tests needing Gene and keep going. Unattended queue C:\scratch\claude\4a72a11b3ea84e15\c233553b-f77d-4b9e-8e31-0e62ebe2831b\scratchpad\finish-queue-20261104.sh (uses CrewChief -run workloads via run-cc-host.sh). TR2 1K bootstrap done 22:18 (SMVM3 lacked Dba domains; Gene deployed them). SMVM2 key now = TR2 main key, so TR1 P2P to SMVM2 likely 401. Synapse 1M 12T export 3h01 > 4T 2h27.
- 11/04 08:20 PLAN (not built, awaiting Gene approval): Connect bootstrap from an EMPTY model (Maestro, no entities) on Main AND P2P target, from a checked-in JSON spec in speed-merchants (50 Dba domains + ids + rows, 120-attr template, entities). Family delete (domains + Connect entities) then rebuild; ref data = replace all rows; foreign entities = warn; P2P target own baseline restored before EVERY P2P run; SMVM2 stays shared (never TR1+TR2 at once); TR1 PDATA-only in same change. Doc: Q:\Work\Work\99 Documentation\speed-merchants\planning\2026-11-04-connect-empty-model-bootstrap-plan.md
- 11/04 08:42 (Gene): 26R2 testing is HISTORICAL only (one round); going forward only new-release testing. So SMVM2 sharing (26R3 P2P target + 26R2 Main) is temporary; empty-model bootstrap targets the current-release box + each new release.

- 11/04 09:10 Gene on Connect docs (Q:\Work\Work\99 Documentation\Connect): D1 Gene generates workloads for new machines and ships them; D2 tester workflows go in shared PROD TestAuto, tagged. D3 (per-environment remote schema) still open, explained in doc 03. Matching reuse: full DB restore per run is fine even at 100M; Matching loads via Connect at max threads; the only per-size variation is which ModelSourceRetailClient<size>.bak (1M, 10M) is restored; existing workflows Matching 1M 26R3 = 10000215, Matching 10M 26R3 = 10000213 (tags Templates,Testing,Current Release,SMVMTR2). CRUD deferred.
- 11/04 09:14 Gene: D3 = option 1 (share remote provider tables; testers warned never to run two boxes at once, no per-env schema). Matching: Connect load not measured; thread count hardware-dependent, default 12; 100M = ModelSourceRetailClient100M.bak; runs on different machines so workloads/workflows must be multi-environment; move Matching tags to the Connect scheme (version + Main machine).
- 11/04 09:32 26R3 Connect round COMPLETE on SMVMTR1 (R3 ALL DONE); finish-queue stopped 09:40. 26R2 on hold until empty-model rebuild. Matching rewrite prompt: Q:\Work\Work\99 Documentation\Connect\04 Prompt - Matching Setup Rewrite (Local, 1K).md; local Main = MyDevProfisee, which Gene builds first (not built 11/04, avoiding 3 Profisee instances at once).
