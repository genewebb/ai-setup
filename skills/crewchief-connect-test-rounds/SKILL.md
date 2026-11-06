---
name: crewchief-connect-test-rounds
description: >
  Run, watch and record a Connect performance test round on the SMVMTR boxes: the CLI runner on each box
  (run-cc-host.sh, queue.txt, the "CrewChief CLI Runner" scheduled task, Run-Queued.ps1, status.json, out\ logs),
  the laptop-side queue scripts (run/pair, RESULT/FLAG/SKIP lines, pause-all), reading a run log (the step label
  of the TestAuto step is the EXECUTION code, step time in ms), the live status board (ConnectTestBoard.html
  BOARD data, syntax check, build-status.sh publish to SMVMTR1), source row counts, and expected run times on
  26R2 and 26R3. Use when starting, resuming or re-queuing a Connect round, doing the 15-minute board refresh,
  recording a result, reading status.json or an out\ log, building a new queue script, changing the board, or
  estimating how long a round will take. For pack internals (reference data, AUTO tags, error-text table) load
  crewchief-workload-packs first.
---

# Connect test rounds (running, watching, recording)

Pack internals, error texts and tweak recipes: [[crewchief-workload-packs]]. Connect pack specifics:
`C:\devops\repos\speed-merchants\CrewChief\packs\connect\CLAUDE.md`. People docs (since 11/06 the ONE source):
CrewChief in-app help, category Packs, sources `speed-merchants\CrewChief\CrewChief.Web\Documentation\60_PacksOverview.md`
and `61`-`64_PackConnect*.md` (overview, new machine, check before a run, run manually). The vault docs
`Q:\Work\Work\99 Documentation\Connect\01`-`03` are pointers (old text in `Archive\`). When a fact here changes (run
times, steps, folders), update those help pages too.

## Test plan (Gene 11/06)

The 26R2 full round (11/04-06, all 54) was for historical numbers only. Next: **26R4 mid-release, then 26R4 GA**,
each on whatever box hosts it (box and version change together: new box = help page "Move to a new machine"; new
version on the same box = "Check before a run", check 3). Performance runs only **1M at 4T**
(`packs\connect\rounds\1m-4t-round.txt`, 9 runs, about 14 h at 26R2 speed). QA runs **1K** (`1k-4t-round.txt`, about
1 h, or the `connect/tests` workloads) plus their own tests. A new box gets the CLI Runner from
`packs\tools\runner\Register-CliRunner.ps1`; SMVMTR2 keeps its hand-made runner (not worth swapping, 11/06).
26R4 has NO Profisee Windows service (service names blank, service steps Skipped) and should perform at or better
than 26R3 (Gene 11/06): 26R2 times are an upper bound for ETAs; flag a 26R4 run clearly slower than 26R3.

## Boxes (as of 11/06; Connect testing closed out 11/06 by Gene)

| Box | Release | Workloads | Profisee servers |
|---|---|---|---|
| SMVMTR2 | 26R2 | Workload pack since 11/04 17:24 (pack workflows 10000317-10000370, tags `AUTO:SMVMTR2:26R2:<key>`). Round complete 11/06 10:58, idle. Runs the pack as restored 11/04: the 11/05 tag edits are NOT on it (they reach the next box with its restore) | SMVM2 app, SMVMDB2 db; P2P target SMVM3 |
| SMVMTR1 | 26R3 | Old generated workloads; move to the pack (plan Task 13) waits on Gene | SMVM1 |

**Only one box runs Connect at a time.** The Databricks, Snowflake and Synapse export tables are shared, so a second
box's prepare drops the table under the first box's run. TR1 stays idle while TR2 runs. Never restart TestAuto
mid-run. Deploy CrewChief or TestAuto only between runs.

## The CLI runner (on each box)

Folder `\\<BOX>\c$\Deploy\CrewChief\cli-runner\`:

- `queue.txt`: line 1 = workload name; further lines = `KEY=VALUE` parameters. A trailing `!` on the name runs
  it as the only child of a generated parent `workloads\cli-runner\cli-wrap-<name>`, the way the Web UI nests it.
- `Run-Queued.ps1`: started by the scheduled task **"CrewChief CLI Runner"** (runs as `CORP\speedmerchants`, so
  Windows-auth SQL steps run locally with no double-hop). It deletes `queue.txt`, then runs
  `C:\Deploy\CrewChief\cli\crewchief.exe run workload <name> --data-folder C:\Deploy\CrewChief\web\data`.
- `status.json`: `state` = `Running` / `Finished` (+ `exitCode`) / `Idle` / `Rejected`, plus `workload`, `started`
  (UTC, so 13:07 = 08:07 EST), `log`.
- `out\<yyyyMMdd-HHmmss>-<workload>.log`: console output (stamp is UTC). Full detail is in
  `C:\Deploy\CrewChief\cli\logs\crewchief-cli-YYYYMMDD.log`.

Checked in since 11/06: `speed-merchants\CrewChief\packs\tools\runner\` (`Run-Queued.ps1`; `Register-CliRunner.ps1` copies
it onto a box and registers the task; `run-cc-host.sh`; `run-queue.sh`). `D:\PowershellScripts\CrewChiefConnect\run-cc-host.sh`
is the older copy the 11/04 queue still calls; prefer the repo copy.

From the laptop: `bash <repo>/CrewChief/packs/tools/runner/run-cc-host.sh <box> <workload> [KEY=VALUE ...]`.
It writes `queue.txt`, runs `schtasks /run /s <box>` (RPC, no WinRM or Kerberos needed), waits for pickup, then
for the outcome, and prints the failing steps.

| Exit code | Meaning |
|---|---|
| 0 | The workload succeeded |
| 9 | Runner busy (`status.json` says Running): wait 30 s and retry |
| 8 | `schtasks` failed |
| 7 | `queue.txt` not picked up in 10 minutes |
| other | The CLI exit code: the workload failed |

## Queue scripts (laptop)

Since 11/06 a round is a LIST file run in the background by the checked-in
`packs\tools\runner\run-queue.sh [--dry-run] <box> <list>` (output appended to a log, always piped through
`sed -u -E 's/[0-9a-f]{32}/[redacted]/g'`). Lists: `packs\connect\rounds\smoke.txt`, `1k-round.txt`, `1m-round.txt`.
A line starting `+` runs only when the line before it passed (import after export), else `SKIP`. Pause file:
`$HOME/crewchief-queue.pause` (or `PAUSE_FILE`). It prints the same RESULT / FLAG / SKIP lines (plus `QUEUE START`,
`QUEUE DONE`), so the 15-minute refresh greps keep working.

The 11/04 style it replaced (a bash script with `run` / `pair` functions,
`C:\scratch\claude\4a72a11b3ea84e15\c233553b-f77d-4b9e-8e31-0e62ebe2831b\scratchpad\r2-queue-emptymodel-20261104b.sh`):

- `run <box> <workload>`: waits while a `pause-all` file exists, retries on exit 9, then prints
  `RESULT <box> <workload> PASS <HH:MM>` or `RESULT ... FAIL rc=<n>` plus `FLAG <box> <workload> failed`.
- `pair <box> <prefix> <provider>`: runs the export `-run`, then the import `-run`. The import is skipped (`SKIP`)
  when the export failed. profisee-to-profisee has no import.
- Order: 1K before 1M; providers sql-server, databricks, synapse, snowflake, profisee-to-profisee; within a
  provider 4T (`connect-<size>-<p>-...`), 8T (`connect-<size>-t8-...`), 12T (`-t12-`), export then import.
- A FLAG is a real failure: note it, keep the queue going; fix and re-queue that cell afterwards.
- Pause between runs: create the `pause-all` file; delete it to resume. Never kill a run in progress.

## Reading a finished run

Last lines of the out\ log (one line per step):

```text
1    TestAutoWorkflowStep          TestAutoWorkflowStep    Succeeded           3 ms        <- Wait For Interrupted Runs
2    Prepare Databricks Export     RunWorkloadStep         Succeeded           4179422 ms  <- reset + source load + prepare
3    Inline                        SqlStep                 Succeeded           119 ms      <- source row check
4    10000396                      TestAutoWorkflowStep    Succeeded           2421867 ms  <- the measured workflow
Outcome: Succeeded
```

- The label of the last step is the TestAuto **execution** code (not the workflow code). The workflow code appears
  in the CLI log line "TestAuto workflow tagged ... is <code>".
- Measured time = that step's ms (2421867 ms = 40 min 22 s). Its start = the RESULT time minus that duration.
- Import `-run`s have no source-load step (3 lines: wait, prepare, workflow).
- Always read logs through `sed -E 's/[0-9a-f]{32}/[redacted]/g'`: a gateway 401 body echoes the API key.

Row counts while a source load runs (read-only):
`sqlcmd -S SMVMDB2.corp.profisee.com -E -C -d profisee` against `data.tPDataSourceImport` or
`data.tPData<Provider>Import` partitions.

## The status board

- Source: `C:\tmp\connect-status\ConnectTestBoard.html` (keep a `.bak-<tag>` copy before big edits). Running
  notes: `C:\tmp\ConnectTestingInProgress.md` (one line appended per refresh).
- Published page: https://smvmtr1.corp.profisee.com/ConnectTesting/Status.html (refreshes itself every 15 min).
- Data lives in `const BOARD = {...}` inside `<script>`: `asOf`, `lastRun`, `running: "<KEY>|<cell>"` (or `""`),
  `runningSince` (start time; add "measured TestAuto workflow since ~HH:MM" once the prepare step is done) and
  `runningEta` (expected finish plus what the guess is based on); both are shown on the running card, and are
  updated whenever `running` changes,
  `eta {made, big[], rows[], note}`, `states`, `sizes` (`1K`, `1M`, `1K 8T`, ...), `connectors`
  (keys SQLSERVER, DATABRICKS, SYNAPSE, SNOWFLAKE, PROFISEE), and `runs`:
  `"<KEY>|<Export|Import> <size>[ 8T|12T]": { s: "pass|fail|run|wait|na", why: "<date> <start>-<end>: workflow <m> min <s> s (<sec> s), execution <code>" }`.
- Add a result by appending a line after the last `runs` entry (add a comma to the previous line), then update
  `asOf`, `lastRun` and `running`.
- Syntax check, then publish only if the check passes:

```bash
S=<scratchpad>/board.js
awk '/<script>/{f=1;next}/<\/script>/{f=0}f' /c/tmp/connect-status/ConnectTestBoard.html > $S && node --check $S
bash /c/tmp/connect-status/build-status.sh
```

`build-status.sh` wraps the board into `Status.html`, copies it to `\\SMVMTR1\c$\inetpub\wwwroot\ConnectTesting\`
and prints `SMVMTR1 200 <bytes> bytes` on success. A failure is usually the laptop off corp DNS or VPN; retry at
the next refresh. The queue is not affected.

### The 15-minute refresh

1. `date`.
2. RESULT, FLAG and SKIP lines of the queue log (redacted), plus `status.json` of the running box.
3. Record each new RESULT (time, execution code, workflow duration from the out\ log) in the board and the md.
4. Syntax check, publish.
5. Report one line: time, new results or none, publish ok or failed.

The refresh never starts or stops runs and never touches TestAuto or another box.

## Run times (workflow = the measured TestAuto step)

| Run | 26R3 (SMVM1) | 26R2 (SMVM2, 11/04-06, round complete: all 54 passed) |
|---|---|---|
| 1K `-run`, any provider | ~7 min (workflow ~186 s) | 6-7 min (workflow 185-246 s) |
| P2P 1K export | ~13 min (target restore ~6 min) | ~9 min |
| 1M export prepare (reset + source load) | not recorded | ~70 min; source load 60-65 min with a slow tail |
| SQL Server 1M export 4T / 8T / 12T | all 6 SQL Server runs ~36 min | 910 / 669 / 548 s |
| SQL Server 1M import 4T / 8T / 12T | (in the 36 min) | 4108 / 2417 / 1935 s |
| Databricks 1M export 4T / 8T / 12T | 4T 50 min 29 s; all 6 runs 2 h 22 min | 3505 / 2422 / 2179 s |
| Databricks 1M import 4T / 8T / 12T | 4T 16 min 02 s | 1513 / 971 / 789 s |
| Synapse 1M export 4T / 8T / 12T | 2 h 27 to 3 h 01 each | 9239 / 9781 / 9181 s |
| Synapse 1M import 4T / 8T / 12T | | 3566 / 2480 / 2538 s |
| Snowflake 1M export 4T / 8T / 12T | Snowflake 2 h 24 min for all 6 runs | 3384 / 1815 / 1334 s |
| Snowflake 1M import 4T / 8T / 12T | (in the 2 h 24 min) | 2055 / 1211 / 910 s |
| P2P 1M export 4T / 8T / 12T | 25 min | 1092 / 670 / 548 s (prepare ~71 min each) |
| connect-setup | 30-40 min | ~20 min |
| Whole round | | 1K 27 runs ~3 h; 1M 27 runs ~39 h; 1M 4T only (9 runs) ~14 h |

26R2 1M runs are 2-7 times slower than 26R3. The cause has not been investigated. 26R4 (next) is expected at or
better than 26R3 (Gene 11/06), so 26R2 times are an upper bound.

## Changing the round

- Re-run one cell: `run-cc-host.sh SMVMTR2 connect-1m-t8-synapse-export-run` (one thread count), or the
  `tests/connect-test-<size>-<p>-<dir>` master (4, 8, then 12).
- New queue: write a list file (copy `packs\connect\rounds\1m-round.txt` and delete lines) and run it with
  `run-queue.sh`; check it first with `--dry-run`.
- New cell or size on the board: add it to `sizes` or `connectors`. The grid is built from those arrays.
- Before restarting a queue, wait for `status.json` to leave `Running`: two scripts racing for the runner was the
  11/04 14:3x "queue race".
