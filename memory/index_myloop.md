# MyLoop index

**[ALL .loop* state WIPED 2026-09-26; zip on NAS is the only copy; entries below describe the OLD loop](project_myloop_state_wiped_2026-09-26.md)**

One line per memory, same format as MEMORY.md.

- [Power cut mid-Executor = recover, never re-dispatch](reference_power_cut_orphan_recovery.md)
- **[MyLoop (/myloop, was MyFable) = THE loop; resumes from <repo>\.loop after any restart (9/13)](project_myfable_foreman.md)** — `/myloop`; rows\<key>.json + Dispatch/Collect/Close/Write-Ledger scripts; proof tiered by class; ≤7 parallel opus workers; never hand-edit the records or the ledger
- [Background loop worker running rm -rf / Remove-Item HANGS on the delete guard forever](reference_background_worker_hangs_on_delete_guard.md) — stale agent transcript = stuck; TaskStop + -MarkLost + re-dispatch; PROMPTS rule 8
- [/myloop TWO-STRIKE RULE: 2 verifier FAILs on a row = close on what passes + carry findings to rows, or split; never a 3rd attempt](feedback_loop_two_strike_rule.md) — 52.S0.3b burned 6 attempts / 7.5 h (9/14)
- [Loop models: Fable plans + verifies, opus executes](feedback_loop_models_fable_plans_opus_executes.md) — start session on Fable; every Executor `model: opus` — **SUPERSEDED 9/13: [opus everywhere — lead, workers, verifier; Fable only per class where high value / low cost](feedback_switch_to_opus_when_fable_burns_tokens.md)**
- [Gate 6 never re-checks earlier CRITERIA](reference_loop_criteria_regression_gap.md)
- [Wave orphaned by a dead lead session: judge each row on its GRADER, never on the missing report](reference_myloop_orphan_recovery_and_script_gaps.md) — fixed 3 script defects (Publish-Done -Url, Dispatch-Row LOST exemption, Close-Row verifier -Override); its Claim-Lead rule is SUPERSEDED by [resume IS the authority grant](feedback_resume_is_the_authority_grant.md)
- ~~OBSOLETE 9/26 (state wiped)~~ **[LOOP PAUSED 9/17 mid restart-gate: read .loop\RESTART-HERE.md first; R14+R17a landed, R17b+WAVE1 owed, hand-implemented while paused](project_loop_paused_restart_here_2026-09-17.md)** — recorded lead-read median 7 min not 18; 93% of open rows have no checkable requirement
- **[Saying "resume" grants authority to reclaim lead + self-heal stale ownership/ticket/Started states](feedback_resume_is_the_authority_grant.md)** — verify PIDs dead, never let the heartbeat auto-dispatch, report what was healed
- [Whole-tree graders invisible to a file-name-keyed census](reference_gate6_whole_tree_graders_invisible.md) — a row adding a test file owes CENSUS-INVENTORY.md a row
- [Gate 6 false REDs: ordering + bare libraries](reference_gate6_false_reds_ordering_and_libraries.md)
- **[MyLoop WAVE is LIVE (9/14): step 9 = Workflow(myloop-wave.js, args = .loop\wave\wave.json); W7 dry run GO; settings.json still owes 2 Bash allow lines](project_myloop_wave_upgrade.md)** — baseline concurrency was 1.02; principles 15 (ui-ux-pro-max) + 16 (Archify for difficult changes) added
- Loops: [orchestrator-worker hardening](project_orchestrator_worker_loop_hardening.md) · [criteria quote-mangling](reference_loop_criteria_quote_mangling.md) · [/myworkflow amendments](project_myworkflow_amendments_2026-08-04.md) · [SkillModelAndDataReview](reference_skillmodelanddatareview.md) · [practices that caught defects](feedback_loop_practices_that_caught_defects.md) · [grader IndexOf ordering blind spot](reference_grader_ordering_clause_indexof_blind_spot.md)
- [schedule.json is the ONLY backup of Write-TaskList.ps1](reference_schedule_json_is_the_backup.md)
- [A malformed Write-TaskList row parses clean and VANISHES](reference_write_tasklist_row_silently_dropped.md) — watch the `N tasks` count
- [Write-TaskList.ps1 is LF: WriteAllLines makes it CRLF, Close-Row throws after the record commits, Reconcile can't repair](reference_write_tasklist_is_lf_writealllines_breaks_close.md)
- [Grader clause shapes that fail (18 defects)](feedback_grader_clause_shapes_that_fail.md) — probe every grader against a wrong AND a correct stub before dispatch
- [PowerShell -match is case-INSENSITIVE; prose answers code clauses](reference_grader_case_insensitive_prose_answers_code.md)
- [Compact checkpoint between rows: ask y/n, 60 s, default n](feedback_compact_checkpoint_between_rows.md)
- [NEVER stop to report between rows](feedback_never_stop_to_report_between_rows.md) — close, dispatch next, THEN summarise; author next grader while an Executor runs
- [Started was TRANSIENT; fixed by append-only started.json + Close-Row.ps1](reference_started_state_was_transient.md)
- [Mark the row Started AT DISPATCH](feedback_mark_row_started_at_dispatch.md) · [orchestrator work counts too](feedback_mark_started_includes_orchestrator_work.md)
- [MyLoop throughput tracking: events.jsonl + Get-Throughput.ps1; lead logs author-reported + rework](project_myloop_throughput_tracking.md) — decide pairing/order on throughput.md figures
- **[NEVER hold a ready legal ticket: dispatch same turn; staleness risk = residual row, not a hold (Gene 9/16 21:16 "NOTHING STARTED")](feedback_never_hold_ready_tickets.md)**
- [New-VerifierPrompt writes .verify.md ONLY with -Wave; a verifier pointed at a missing file may improvise and run live-stack graders](reference_myloop_verifier_prompt_needs_wave.md)
- [Digest-pinned proof receipts go RED on ANY parallel rebuild: re-certify at section close, never mid-wave](reference_digest_receipts_stale_on_any_rebuild.md)
- **[MyLoop HARDENING 9/16 LANDED: R1-R7, R10, R11 (chaos 27/27 vs baseline red, suite 27/27); R8/R9 PARKED; loop PAUSED on Gene's maintenance hold](project_myloop_hardening_2026-09-16.md)** -- graders/suite run ONE AT A TIME through the space-free alias; never delete the baseline or staging copies; report in LoopOptions
- [Autoresearch for MyLoop 9/16: BUILD AFTER RELIABILITY HARDENING; lexicographic fitness (L0 hard constraints zero, then reliability, est-min/hour, tokens); immutable evaluator = workload bundle + replay oracle + chaos suites; best-known as folder copies, promotion only via a row](project_autoresearch_for_myloop_2026-09-16.md) — blocked on 48.R11; rescue replay.py first
- **[MyLoop vs AIWorkHub/Superharness 9/16: KEEP MYLOOP; seats 45% no-ticket / 13% lead latency / 9% busy; 12 shadow false-READYs on exclusive; 6 crash-stranding shapes to fix (atomic writes, dispatch journal, auto-LOST)](project_myloop_replacement_evaluation_2026-09-16.md)**
- **MyLoop (/myloop = THE loop): ALL .loop* STATE WIPED 9/26, start fresh; archive D:\DataArchive\myloop-2026-09-26 [wiped](project_myloop_state_wiped_2026-09-26.md) · [index](index_myloop.md)**
- **[/myloop RETIRED 9/27 for new work: green-field stream kit (1 role/session, worktrees, patches; role inboxes + /stream-kit inbox; /stream-coordinator supervisor 9/28)](project_stream_kit_replaces_myloop.md)**
- **[MyLoop: full suites run ONCE at group close-out; row graders targeted tests only](feedback_run_suites_once_at_group_close.md)**
- **[MyLoop: fixes sharing a write set = ONE row; per-row overhead is the estimate](feedback_one_row_per_write_set.md)** · [Write-TaskList.ps1 must stay LF, Set-Content CRLF breaks Close-Row](reference_myloop_tasklist_must_be_lf.md)
