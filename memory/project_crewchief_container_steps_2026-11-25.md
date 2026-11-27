---
name: project_crewchief_container_steps_2026-11-25
description: "CrewChief ssh transport + container steps 11/25 (ba64e0c8, live a99164a8); Connect container lane switches d6392079 + Providers fd44bd51; pair CrewChief in C:/Deploy/CrewChief-Pair, waiting on Gene secrets"
metadata:
  node_type: memory
  type: project
  originSessionId: 7986e46e-eb36-4bdb-a0ee-12f91e19b099
  modified: 2026-11-25T05:06:42.519Z
---

Gene 2026-11-24 23:50 (design D25/D26 in planning/Design_CrewChief_ProfiseeContainerTesting.md): CrewChief reaches
both lab VMs with ssh.exe through the Proxmox host (ProxyCommand nc, key sign-in, accept-new host keys); build
transport, then WindowsContainer and SqlContainer steps. Built and committed ba64e0c8 on
bug/isolation_testing_linux/genewebb; unit suite 4728 green (ContainerStepTests).

- Engine/Executors/Ssh (SshEndpoint, SshArguments, DefaultSshCommandRunner), Steps/SshStepBase.
- WindowsContainerStep actions Login/Pull/Run/Configure/WaitHealthy/Logs/Stop/Remove; values as base64 JSON on
  stdin; Configure = docker exec -i with fixed encoded inner script (recipe D24, see [[reference_profisee_container_hostname_binding]]).
- SqlContainerStep Deploy/Verify/Remove; .env mode 600; read-back keys compared in C#; Verify finds the container
  by compose labels, so it works on the harness-made tai-psql project too. tempdb tmpfs not ported.
- Not box-prep (no CredentialSecretName), so box-prep census unchanged; executor census 31.

Live 2026-11-25 01:15 (a99164a8): ContainerStepsIntegrationTests (RemoteLab, CREWCHIEF_SSH_TEST_* env vars) 4/4 pass.
App VM sshd: Administrator key only (administrators_authorized_keys), PasswordAuthentication no; built-in rule is
Private-profile only and the VM networks are Public, so rule TAI-OpenSSH-22 (TCP 22, 172.16.10.0/24). Known hosts:
C:\ProgramData\TestAutoIsolation\ssh\crewchief_known_hosts. Not live yet: SqlContainer Deploy (.env), Configure.

**Why:** app VM not domain-joined and only 443 forwarded, so WinRM design (C4) was dropped.
**How to apply:** live test needs OpenSSH Server enabled on the WS2025 app VM (after any measured run), keys, and
the host as jump. Never run against CorpProxMox01 during a measured run.

**Connect container lane (Gene D27/D28 + 11/25 11:1x), committed d6392079 11/25 11:41.** Pack switches, Windows
defaults in checked-in reference sets; the pair sets its own values in its own CrewChief data folder:
- `AppHost` windows|container (+ 7 `Container*` ssh values, connect/machines): common stop/start/pools act on IIS or
  the whole container (`{{AppHost|map:container=true,*=false}}` gates). Seed restore + install/configure skipped on container.
- `SqlAuthMode` Windows|Sql + `SqlLoginUser`/`SqlLoginPassword` (secret tokens): DatabaseOperations/SetApiKey steps
  come as a gated pair because executors compare raw authMode to "Sql" (a token there = Windows silently).
- `SqlSignIn` (connect/databases): replaces `Integrated Security=True` in BOTH SqlStep connections (the executor opens
  source and destination). Value may hold `{{$config:...}}` tokens (26cbfea7).
- `RunWith` testauto|connex (connect/environment): connex = ConnExStep Execute IntegrationStrategy + WaitForBatch on
  StrategyName; Gene chose ConnEx because TestAuto overrides take only literal secrets (PROD DB).
- Known not handled: common-base-backup-check + connect-preflight backup checks join with `\`, xp_fileexist on Linux
  unverified, CombineServerPath `\` (snapshots/relocate only).
- `Providers` all|sql-server (connect/environment, fd44bd51): sql-server skips cloud provider steps; ungated TestAuto
  steps follow RunWith. Docs: help 61 table, pack CLAUDE.md (30146af3).
- **Orchestrator resolves a step's merged parameters (globals + step params) BEFORE runWhen**, so a skipped step's
  `$config` parameters must still exist in the store (pair template carries placeholders for cloud providers).

**Pair CrewChief (Gene 11/25 11:5x):** CLI d6392079 published to `C:\Deploy\CrewChief-Pair\cli`; its appsettings set
DataFolder `C:\Deploy\CrewChief-Pair\data` + SecretsFolder `C:\ProgramData\CrewChief-Pair\secrets` (ACL copied from
main store). Deployed CrewChief (11/16, 9de581d7) untouched. Pair values set by scratch `pair_refs.py`; `restore` needs a
`reference-kv/backup-location.json` first (path `C:\Deploy\CrewChief-Pair\Backups`). Gene fills
`C:\Tmp\pair-secrets-template.json`, imports, `unlock` (sealed.json copied). Pair SQL: ModelSourcePDATA1K.bak and start
backup `profisee_pair_start_20261125.bak` (empty configured DB) in `/var/opt/mssql/data`; xp_fileexist works on Linux.
Gotcha: Test-Pack/New-PackBackup with a RELATIVE -PackRoot fails sibling-pack lookup (54 false problems); use absolute.
`Select-Object -First N` after New-PackBackup stops the script before the zips are written.

**Lane proven 11/25-26:** pair `connect-base-create` passed (run 2, after a693dcb8 added the ModelSource restore before
the export table); one 1K SQL Server export + import through ConnEx passed (1000 rows). Real batch time is in
`connex.tBatch` ($EnterDTM to $LastChgDTM): about 5 s of a ~200 s run; CrewChief WaitForBatch polls every 30 s, so
its step time is not the batch time. Gene 11/26: busy check loops full runs (restore, restart, batch), split reported.
Busy-pair Short check `20261126-100202-phase-busy-pair-short-check` started 10:02 with scratch `busy_loop.ps1`.
Read-only SQL on the pair: scratch `pair_sql.py <file.sql>` (query over stdin, avoids sh quoting).
11/26: busy check 10:02 invalid: an ssh session to the app VM signed in but Windows sshd never started the command
(`sshd -z` child left alive, no shell), container Stop waited 600 s. Gene: pack-only fix, container steps 120 s/attempt
+ 2 retries (common gen). Rerun `20261126-133104-phase-busy-pair-short-check-2` 13:31. Test-Pack needs `-Family <pack>`
(without it common FAILs "reference folder missing").
11/26 15:xx CORRECTION: busy run 2's 2x network (net.rt 35->79 ms) was NOT the Connect loop: step came 10:40:30 after the
loop stopped. qemu-ga on the app VM (9302) spun one CPU (99%); app VM shares L3 chiplet 78-83 with the far end. Fix =
Restart-Service QEMU-GA (kvm 107%->22%). Check: split TAI blocks.jsonl (C:\Deploy\TestAutoIsolation\web\data\tests\<id>)
by observation startedUtc (scratch onoff.py). Jump leak: every ssh via ProxyCommand `nc %h %p` leaves its nc on the
host (39 ended 11/26); transport fix open (e.g. ssh -J / nc -N). Commits ff67cf3b (retry), 62fce96a (records).
11/26 15:41 REAL CAUSE of 2x network: far end VM 9200 root disk 100% full: far agent Docker json log 9.16 GB (ASP.NET
info line per /net/echo, no rotation), last write 10:40:27 = step time; rsyslogd/journald spun. qemu-ga restart did NOT
help (proof 1 still 78 ms). Truncated (note 10 U22). TAI 14.10.0 (fffdcdd1): compose logging json-file 50m x 3 on every
service + agent env Logging__LogLevel__Microsoft.AspNetCore=Warning (image 1.7.0 unchanged). Installer built, not yet
installed. Redeploy recreates SQL containers too (compose changed for sql service): tell Gene.
11/26 16:00 idle proof 2 PASSED (net.rt 35.4 ms, all within 3% of 11/24 idle) = far end disk was the cause. TAI 14.10.0
installed 16:04, cpm01-smoke redeployed 16:07 (note 10 U23, log cap + quiet env read back). Gene: idle proof 3 on new
stack first (20261126-161132-phase-idle-proof-3-tai-14-10, P3 profile seed 52), then busy-pair rerun. Commit 5e437261.
11/26 17:48 busy-pair check 3 VALID (a9979639): no neighbour median moved; net.rt NotDecided but idle proof 3 on new
stack already scatters (iso1 cov 13.6% vs 2.0%), so cause open. Batch 5.4 s of 194 s run. Far end L3 78-83 shared with
app VM cores 80-83 (sysfs). LESSON: never compare across a redeploy; get like-for-like idle first. Gene: idle Short check
on new stack 20261126-175907-phase-idle-pair-short-check-ta (U5 profile seed 52) running; decided at idle = pair causes.
11/26 19:20 STEP 4b PASSED: idle Short check on new stack (20261126-175907) net.rt also NotDecided, same cov 4.2% as busy;
pair cleared, far end stays. Gene: step 6 = ONE P7 day tonight ('Plan P7 - Standard every instance Report v2', 520 blocks,
~11 h) + Connect loop (busy_loop.ps1 -MaxHours 13): test 20261126-194854-phase-step6-real-load-p7-day1 started 19:48.
Judge vs pooled verdict days; add days only if unclear. Then step 7 needs Gene OK to remove iso1/iso2.
11/27 02:10 step 6 busy P7 day 1 VALID (2239b3f3): levels = idle on same stack; not decided mem/sql.write/commit from 3 big
outlier pairs (>3x margin) vs 1 per verdict day. P7 now 6.3 h not 11 h: gap between blocks 46 s -> 12 s (later TAI). 19/84
loop runs slow in Prepare step (340-540 s), cause not checked, matters for step 7. Gene: idle P7 day first
20261127-101247-phase-step6-idle-p7-day1 (10:12). Idle has same outliers = stack, step 6 passes; idle clean = more busy days.
11/27 11:35 Gene: OK remove iso1/iso2 (after step 6 settles); sign-in assumed OK; secrets + C:\Tmp cleanup on SUNDAY; do all
possible before. Step 7 decided: ConnEx lane timing (batch from connex.tBatch + steps + whole run, 3x A/B), app VM = full
clone of 9302 -> 9312 node 0, DB stack cpm01-profisee2 VM 9311 node 1, one pair CrewChief w/ box sets
(docs/isolation/profisee-phase/scripts/boxset.py; sets in C:\Deploy\CrewChief-Pair\boxsets\A|B), runbook in
Windows-Phase-Plan.md step 7 (8b68bcf7). Slow Prepare = app VM ssh hang (sshd accepts, command never starts) caught by
120 s timeout+retry 20x in step 6; look into it after idle P7. b233d7de: SQL backup paths use server separator.
Clone keeps 9302's ssh host key: add 172.16.10.122 to crewchief_known_hosts after clone.
