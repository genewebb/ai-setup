---
name: project_myloop_replacement_evaluation_2026-09-16
description: Verdict and measured evidence from the 2026-09-16 evaluation of replacing MyLoop with AIWorkHub or Superharness (KEEP MYLOOP + hardening list)
metadata: 
  node_type: memory
  type: project
  originSessionId: 39f80102-2320-40e6-a21c-5931aa56d469
  modified: 2026-09-16T14:17:29.307Z
---

**Verdict (2026-09-16): KEEP MYLOOP.** Report + Archify diagram + spec in the vault at
`Q:\Work\Work\03 Shared\work-ai\Loops\LoopOptions\` (MyLoop-Replacement-Verdict.html, -Diagram.html, .workflow.json;
written through Write-VaultFile.ps1); Artifact https://claude.ai/artifact/UuVnRHcuft9iJNob7Cks2D. Gene wants future
loop-option reports in that LoopOptions folder. Scripts were in the session scratchpad (`replay.py`, `Inject-Faults.ps1`).

**Why:** (1) seat loss is supply-bound: 7 seats × 951 min replay window = 6,657 seat-min; 44.6% no ticket, 27.2% real
after/gate dependency, 13.0% lead latency (legal ticket waiting, seat free), 9.1% busy, 5.2% exclusive, 0.8% writeSet.
Live board 207 open / 200 no ticket. (2) Shadow replay over 27 real dispatch epochs: a deps-only (Superharness-shaped)
or deps+write-scope (AIWorkHub-shaped) scheduler would have released 12 rows into an exclusive stack/warehouse MyLoop
correctly held (+1 same-file overlap for deps-only); MyLoop had 0 rule-caused false BLOCKED. (3) Neither runs here as
shipped: AIWorkHub task creation is gated on a VS Code-hosted Claude parent (`entrypoint: "claude-vscode"`; ours is
`cli`) and Windows launch is blocked by 2 bugs (kernel32 vs kernelbase `DeriveCapabilitySidsFromName`; no
`windows_appcontainer` branch in `sandbox_argv`); Superharness hard-codes `bash` + util-linux `script` on dispatch
(escape `SUPERHARNESS_NO_PTY_WRAP=1`), and neither models `exclusive`/`testProject`.

**MyLoop defects measured by crash injection (fix these, ~1-2 days):** non-atomic `Write-Json` (15 WriteAllText sites,
0 temp+rename): a torn row JSON or dispatched.json stops EVERY script (F8/F9); Dispatch crash after Write-Row strands a
row (F1); Close crash after board Close-Row strands a collected row with no dispatched.json entry (F6); two concurrent
Dispatch-Row calls lose a dispatched.json entry and wave.json keeps only the last (F10); nothing marks LOST without a
human (F3); no cycle diagnosis in `after` edges. Re-collect is idempotent (F4/F5). Own test suite 18/18.

**Override census:** 39 of 82 closed rows closed with -Override; 35 failed checks were `regress:*`; 19 rows had ONLY
attribution-class failures (48.WAVE1 shape).

**Why:** the user asked for a burden-of-proof evaluation; every figure above is measured, so future "should we swap
the loop" questions should start from these numbers rather than READMEs.
**How to apply:** if asked again about AIWorkHub/Superharness, re-run `replay.py` on the current events and re-check
whether the two AIWorkHub Windows blockers and the VS Code identity gate still exist before spending time. Borrow
patterns only: version-checked row writes (Superharness), epoch-fenced claims + dispatch journal replay (AIWorkHub).
Related: [[project_myfable_foreman]], [[project_myloop_wave_upgrade]], [[project_myloop_throughput_tracking]].
