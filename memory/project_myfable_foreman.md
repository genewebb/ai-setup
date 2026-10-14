---
name: project_myfable_foreman
description: MyLoop (/myloop, formerly /myfable) is THE loop for the speedy programme; one loop per repo, state entirely in <repo>\.loop, resumes after any restart
metadata: 
  node_type: memory
  type: project
  originSessionId: 1c9afcba-fb90-4c16-9d40-a5770418aa15
  modified: 2026-09-12T21:14:19.044Z
---

**MyFable Foreman** — skill `Q:\Work\Work\03 Shared\work-ai\skills\myfable-foreman\` (SKILL.md, PROMPTS.md, scripts\), command `/myfable`. Built 2026-09-12 17:0x–17:2x on Gene's instruction ("redesign the most efficient loop/foreman around the same principles ... call that MyFable Foreman") after measuring the old stack on 52.P1.1a: worker 8 min, orchestrator bookkeeping 13 min.

**Why:** the orchestrator had become a clerk — four hand-written records per dispatch, a 1,500-char board essay per close, a blind verifier on every static-HTML row, 30-min heartbeat lag. Gene's decisions: whole programme (not just row 52), proof tiered by row class, up to 7 parallel workers on disjoint write sets.

**How to apply:**
- Every row = `.loop\PLAN-<key>.md` with YAML frontmatter (key, class, grader, selfTest, est, writeSet, files/uiHome for mockups, build/test for code, crosscheck for security) + `.loop\rows\<key>.json` written by the scripts. Never hand-edit rows, dispatched.json, actuals.json or the ledger (`Write-Ledger.ps1` regenerates it; decisions go in `.loop\rows\_decisions.md`).
- Turn: `Dispatch-Row.ps1 -Keys a,b,c` (refuses green grader / failed self-test / overlapping write sets / unapproved gate; prints Agent params + Monitor command + prompt) → publish → Agent + Monitor per row → on wake `Collect-Row.ps1` (class checks, verdict sheet) → read → `Close-Row.ps1 -Minutes -Residual` (wraps the board's Close-Row, actuals, one-line status, regen) → publish → `Write-Ledger.ps1`.
- Proof tiers: mockup = grader + classes-exist + sample-data.js executes + secrets grep + repos clean, verifier ONCE per batch before the gate; doc = grader + scope; code = grader + build + tests(floor) + constraint + changed files, verifier EVERY row; security = code + crosscheck list.
- Gates: `Approve-Gate.ps1 -Key 60 -By Gene -Note` only on Gene's word; `afterGate:` rows are refused until then.
- Old skills stay installed for other repos; for this programme use only /myfable. PowerShell trap that bit this build FOUR times: a lowercase `$p` loop var shadows `$P`; `$stamp:` is a scope qualifier — use `${stamp}`.

Related: [[project_mockup_calibration_line]], [[feedback_loop_models_fable_plans_opus_executes]], [[reference_powershell_switch_param_shadows_local_var]], [[project_speedy_crewchief_section_plan_2026-09-12]].

**Script fixes 2026-09-12 19:4x–19:54 (vendored in work-ai; an upstream update would REVERT them):** (1) `RowCommon.ps1 Set-BoardStatus` now matches BOTH tuple shapes, `@('52.P1.3a', ...)` and the integer gate rows `@(60, ...)`; before the fix `Approve-Gate.ps1` wrote `rows0.json` and then threw, so Gene's 19:18 approval never reached the board and no regen ran. (2) `Write-Ledger.ps1` uses a `Prop` helper because a gate record has no seat/est/actual/residual and StrictMode throws on `.Value` of a missing property. (3) Known hazard: `Write-TaskUpdate.ps1` fails with "being used by another process" when `speedy\detailed_task_plan\CrewChief-Section-Plan.html` is held open over SMB; Dispatch-Row has already written the row and dispatched.json by then, so treat it as "retry the two vault pages", not as a failed dispatch. (4) The harness may not expose `foreman-worker` as an Agent type ([[reference_foreman_agent_types_not_exposed_after_q_remap]]); fall back to general-purpose + `model: opus` + the contract pasted in.


**2026-09-13 20:2x update — renamed to `myloop`.** Skill at `Q:\Work\Work Shared\work-ai\skills\myloop` (symlinked as `~/.claude/skills/myloop`; the old folder is `myfable-foreman-prev-2026-09-13`). `/myloop` with no arguments resumes from `<repo>\.loop\`; `pause`, `resume`, `status`, `next <keys>`. New scripts: `Sync-Board.ps1` (every wake), `Set-Pause.ps1`, `Claim-Lead.ps1`, `Publish-Done.ps1`, `New-VerifierPrompt.ps1`, `Write-VaultFile.ps1`; config `.looporeman.json`; state `.looporeman-state.json`. 19 fixes listed in the skill's `CHANGES.md`, each with a test in `tests\Test-MyFableNext.ps1`. Rules now in scripts: per-row dispatch snapshot, regression graders at collect, calibrated timing, lead lock, pause, board guard, no prompts, pages regenerated at every state change.
