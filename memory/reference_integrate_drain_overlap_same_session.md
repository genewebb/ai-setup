---
name: reference-integrate-drain-overlap-same-session
description: "Two background Integrate-Patch drains under ONE integrator session both pass the integrator lock (it checks session, not process) and race; start a new drain only after the previous one's completion notification"
metadata:
  node_type: memory
  type: reference
  originSessionId: 4599ecab-4540-423c-841b-aeba6b8760d1
  modified: 2026-10-02T05:23:28.502Z
---

2026-10-01, SMVMTR1: a background drain (`for` loop over Integrate-Patch.ps1) was read as finished from its partial
output file, and a second drain was started under the same session. Integrate-Patch checks `.streams\integrator.lock`
by SESSION, so both passed. For about an hour they raced. One REBASE-bounced G3.T019/G3.T026 while the other committed
them (e75a86f, 2e9a997). A concurrent `git add` hit `.git/index.lock`, so G3.T004's commit failed. The builder then set
both tasks `blocked` ("already met"). Only `plan` may move a task out of `blocked` (Streams.ps1 Transitions).

**How to apply:** a background task's output file is not its status. Wait for the task-notification, or check
for the live pwsh process (`Win32_Process` CreationDate plus children) before starting another drain. Kit fix asked in
IN-20261001215631-6eda (per-process guard, plus a blocked>integrated move for already-met patches).

**Happened AGAIN 2026-10-02 00:3xZ.** A `Win32_Process` filter on `CommandLine -match 'Integrate-Patch'` found nothing. A
background drain is ONE pwsh whose command line is the whole `for` loop, and the loop calls Integrate-Patch with `&` inside
that process. So no child process names the script, and the old drain looked dead. **Only** the harness task id is
reliable: a drain is live until its `<task-notification>` arrives, whatever any process probe says. Note every drain's
task id, and before you start another drain, TaskStop the old one or wait for its notification. Cost that time: G3.T056
was applied and reversed by hand mid-grade, then the old drain re-applied and committed it (25be1e1).

A run longer than 2 h (a full step-B run, or a drain of 25+ patches) is killed at the harness's background limit, possibly
mid-patch. Launch it with `Start-Process pwsh -File <script> -PassThru`, write its PID to decisions.md, and wait on that PID,
not on a harness task. Since kit v0.5, Integrate-Patch also holds `.streams\integrate-patch.lock`: a second run exits 4
(DRAIN-BUSY).

Related: [[reference_stream_kit_update_task_needs_beat]]
