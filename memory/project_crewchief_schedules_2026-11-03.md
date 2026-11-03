---
name: project_crewchief_schedules_2026-11-03
description: "11/03 decisions: CrewChief Schedules feature (Windows Scheduled Task) + RunTestAutoWorkflow step; connect folder layout providers/<p>/<size>/t4|t8|t12; cli-wrap obsolete"
metadata:
  node_type: memory
  type: project
  originSessionId: 4dd36d8c-694d-4696-be28-10c24d7ba30b
  modified: 2026-11-03T20:22:56.354Z
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

**Why:** Gene wants daily/weekly unattended Connect runs owned by CrewChief, not bash on the laptop.
**How to apply:** design new work against this; speed-merchants = no commits by Claude (git-guard), Gene commits.
