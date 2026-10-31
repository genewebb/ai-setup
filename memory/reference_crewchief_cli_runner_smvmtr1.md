---
name: reference_crewchief_cli_runner_smvmtr1
description: Claude runs CrewChief workloads unattended on SMVMTR1 via scheduled task 'CrewChief CLI Runner' (corp\speedmerchants) + queue file; remoting CLI fails SQL double-hop; ConnEx top-level preflight needs '!' wrap
metadata:
  type: reference
---
CrewChief CLI over Invoke-Command (laptop -> SMVMTR1 as agenewe) fails Windows-auth SQL steps: `Login failed for user 'NT AUTHORITY\ANONYMOUS LOGON'` (Kerberos double-hop).

Fix (Gene registered 10/30): scheduled task **'CrewChief CLI Runner'** on SMVMTR1, runs as **corp\speedmerchants** (same account as the CrewChief Windows service), action `pwsh -File C:\Deploy\CrewChief\cli-runner\Run-Queued.ps1`.
- Queue: write `\SMVMTR1\c$\Deploy\CrewChief\cli-runner\queue.txt` (line 1 = workload name, more lines = KEY=VALUE params), then `Invoke-Command -ComputerName SMVMTR1 { Start-ScheduledTask 'CrewChief CLI Runner' }`.
- Result: `cli-runner\status.json` (state Running/Finished/Rejected, exitCode, log) + `cli-runner\out\<stamp>-<name>.log`. Engine detail in `C:\Deploy\CrewChief\cli\logs\crewchief-cli-<date>.log`.
- Helper (session scratch, recreate if gone): run-cc.sh queues, starts, waits, prints non-succeeded steps.
- **Trailing `!` on the name** = run as only child of generated parent `workloads\cli-runner\cli-wrap-<name>`. Needed because top-level **ConnEx preflight (exit 4) ignores the workload's own Global Parameters** and --param ({{ConnExBaseUrl}} "no source") although the same workload runs fine nested. Suspected CrewChief preflight defect, not yet fixed.
- `secrets status` on SMVMTR1: machine-shared store C:\ProgramData\CrewChief\secrets, unattended master available.

TestAuto has NO HTTP endpoint or CLI to start a workflow (Blazor UI only) -> that stays Gene's manual step.
Related: [[project_connect_test_board_2026-10-30]]
