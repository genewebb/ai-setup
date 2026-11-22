# Stream kit index

One line per memory, same format as MEMORY.md. Critical stream rules stay bolded in MEMORY.md itself.

- [Stream kit: mtime grader clause always red on main after integrate](reference_stream_kit_mtime_grader_clause_breaks_on_integrate.md) — send to planned, don't rebuild
- [stream-plan 9/27: G3 Steps / G4 Workflows / G5 / G6 released, 335 tasks, page links](project_stream_plan_g2_g6_released_2026-09-27.md)
- [Update-Task needs -Beat or the watchdog steals the task](reference_stream_kit_update_task_needs_beat.md)
- [Stream-author takeover race: old session may still write; hash ticket/grader at claim, re-check before writes and RED sha before release](reference_stream_author_takeover_race.md)
- [.streams board is UNTRACKED (.git/info/exclude), 0 tracked files — same exposure .loop had before the wipe; no backup, only a /MIR mirror](reference_streams_board_untracked_like_loop.md)
- [Grader needs regex starting with | always matches; PS comma/plus precedence creates it](reference_grader_needs_regex_leading_pipe_always_matches.md) · [grader line anchor `[^\r\n]*$` never matches in a CRLF tree — end it `(?=\r?\n|$)`](reference_grader_line_anchor_unreachable_in_crlf.md) · [grader trx reader: a DataRow testName has a space before `(`, so split-on-`(` leaves a trailing space and the test reads as "did not run"](reference_grader_trx_datarow_name_has_trailing_space.md)
- [Grader ORDER clause must skip function bodies](reference_grader_text_order_is_not_execution_order.md) — helpers sit above the main flow, so the first textual match runs last
- [Verifier subagent can stall for HOURS at zero output while the builder keeps beating; no watchdog sees it](reference_verifier_subagent_stalls_while_builder_beats.md) - bound in stream-build step 7
- [stream-build: dotnet test does NOT beat the claim; watchdog reaps the worktree mid-build](reference_stream_build_beat_during_long_builds.md) — beat every few minutes; never keep the session id in D:\tmp
- [Owner queue: '- ' bullets are the real escalations, unprefixed lines are applied defaults](reference_stream_owner_queue_bullets_are_the_escalations.md) — RESOLVED token in place, override still needs an inbox item
- [Stream mockup deliverables built under D:\tmp get lost; verdict file gallery URL is the recovery path](reference_stream_mockup_deliverables_lost_from_tmp.md) — a grader with an absolute -Sheets default reads GREEN off the stale copy
- [Stream inbox item can be re-opened while held → two sessions duplicate the work](reference_stream_inbox_item_reopened_while_held.md) — re-read the item tail before writing and before `done`
- [Stream claim order is group-first BY DESIGN (2026-09-30), 4 tests lock it](reference_stream_claim_order_is_group_first_by_design.md) — run Test-StreamKit.ps1 BEFORE editing any kit script
- [Kit install: a drift check that only REPORTS clobbers another session's script](reference_kit_install_drift_check_then_copy_clobbers.md) — Test-StreamKitRecovery.ps1 is the collision point; on drift stop, diff, merge
- [Add-Tasks overlap counts INTEGRATED rows and GLOB write sets as owners](reference_add_tasks_overlap_counts_integrated_and_globs.md) — edge needed on landed rows; reverse a glob edge in the same Revise batch
- [Revise-Task folding work into a TICKETED row: ticket never covers it, work dropped](reference_stream_revise_ticketed_row_work_not_in_ticket.md) — fold only into planned/blocked rows; `release auto` cannot un-build a built row
- [Kit stages in D:\tmp\streams wiped by watchdog sweep (Copy-Item keeps old mtimes): touch files, publish same session; transcript replay recovers](reference_kit_stage_wiped_by_watchdog_sweep.md)
- [Kept worktree with owner files OUTSIDE = base failed part-way, nothing staged](reference_stream_kept_worktree_outside_means_failed_base.md) — check `diff --cached`
- [PS comment-help under #Requires is invisible to GetHelpContent; add a blank line](reference_ps_help_after_requires_needs_blank_line.md)
- [Update-Task retry loop: `$o -notmatch` on array output breaks early; Out-String, set artifacts+release in ONE call](reference_stream_retry_loop_array_notmatch.md)
- [PS var names case-insensitive: loop $cls clobbers $Cls, check impact entries never judged](reference_ps_case_insensitive_var_collision_in_checks.md) — prove a class entry can go red
- [No retire state: superseded blocked row holds OPEN-ROWS; owner-approved locked write blocked -> done](reference_stream_retire_superseded_row.md) — G4.T075 10/9
