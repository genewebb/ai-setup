---
name: project_myloop_wave_upgrade
description: "WAVE-UPGRADE (2026-09-14): pending 7-item plan in the myloop skill to run each wave's worker→collect→verifier→sync as a Workflow script (myloop-wave); /myloop offers the next open item on wake; measured baseline concurrency 1.02"
metadata: 
  node_type: memory
  type: project
  originSessionId: 70ac3844-22d8-4b08-94bd-6a9c7eee7afb
  modified: 2026-09-14T20:43:47.086Z
---

**Plan lives at `Q:\Work\Work\03 Shared\work-ai\skills\myloop\WAVE-UPGRADE.md`** (CHANGES.md row 20, SKILL.md
"Pending upgrade", `/myloop` command text). Items in order: W5 permissions → W1 `Dispatch-Row -EmitWave` →
W3 `Collect-Row -Json` → W2 `~/.claude/workflows/myloop-wave.js` → **W7 dry run = go/no-go** → W4 skill text →
W6 sync stage. About 4.5 h, uncalibrated. Archify diagram: `99 Documentation\Goals\MyLoop-Supercharged.workflow.html`.

**Why:** measured from `.loop\rows\*.json` on 2026-09-14 (27 rows, 45 attempts): average concurrency while any
worker ran was **1.02** with `maxParallel` 7 — the loop ran serially; lead collect→close median 8 min (code) /
20 min (security); worker tokens per attempt median code 157k, security 270k, mockup 197k. Every
collect-every-worker / never-re-dispatch rule was remembered by the lead, not enforced.

**STATUS 2026-09-14 16:45: W1–W7 DONE, the wave is LIVE.** `Dispatch-Row.ps1` writes `.loop\wave\wave.json` +
`<key>.prompt.md`; `Collect-Row.ps1 -Json`; `New-VerifierPrompt.ps1 -Wave`; `skills\myloop\workflows\myloop-wave.js`
(invoke by `scriptPath`, args = wave.json object); SKILL.md steps 2/4/8–10 + principles 15 (ui-ux-pro-max on every UI
change/mockup) and 16 (Archify diagram for a difficult change); test 17 `wave:` in Test-MyFableNext.ps1 (17/17 green).
W7 dry run on `C:\tmp\wave-dry`: 7 agents, 4m56s, 407k tokens, no permission stall (agents use the PowerShell tool).
Still open: `~/.claude/settings.json` lacks the two `Bash(pwsh -NoProfile -File C:/Users/agenewe/.claude/skills/myloop/scripts/*)`
entries that permissions.yaml now carries (harness refused the self-edit; Gene adds them); first REAL wave owes the
timing comparison.

**How to apply:** step 9 of the per-turn procedure is now the wave; the Monitor-per-row path is the fallback only.
Facts settled this session: a subagent CAN spawn subagents (tested); `AskUserQuestion`, `ScheduleWakeup` and
`Workflow` are ABSENT inside a subagent (tested) — so the lead stays in the main session and only the wave becomes
code. Whether workflow agents can run pwsh under the allow-list unattended is UNTESTED (W7 decides).
Related: [[project_myfable_foreman]], [[feedback_run_parallel_when_possible]], [[reference_power_cut_orphan_recovery]].
