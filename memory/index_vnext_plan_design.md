---
name: index_vnext_plan_design
description: Index of vNext (speedmerchants) plan-document and design memories
metadata:
  type: reference
---

Moved out of MEMORY.md to keep the index under its read limit; each line keeps its original links.

- vNext plan: [v3 is the plan doc](reference_vnext_plan_doc_v3.md) · [Fable review 9/3](project_vnext_fable_review_2026-09-03.md) · [UoW-8b+8c closed](project_speedmerchants_uow8b_8c.md) · [SUT testbed](reference_speedmerchants_vnext_sut_testbed.md) · [dual RunProfile migrator](project_speedmerchants_dual_runprofile_migrator.md) · [UI tests Playwright reuse](project_vnext_ui_testing_playwright_reuse.md) · [R28 topology/roles](project_vnext_r28_topology_roles_installer.md) · [re-plan 9/4](project_vnext_replan_2026-09-04.md) · [A3 decisions](project_vnext_a3_decisions_pending.md) · [A2.3f probe](project_vnext_a23f_master_bootstrap_probe.md) · [planning sweep 9/5](project_vnext_planning_sweep_2026-09-05.md) · [D7 engine-agnostic port](project_vnext_workflow_engine_agnostic_port.md)
- vNext design: [workload = CrewChief bundle](project_vnext_workload_bundle_format.md) · [filter editor](project_vnext_filter_editor_design.md) LOCKED · [run-profile](project_speedmerchants_run_profile_design.md) · [Monitor UI](project_speedmerchants_vnext_monitor_ui.md)

## Speedy build, testing, plans and stream kit (moved 2026-10-01)

- **TESTDATA: [CLOSE-OUT PLAN 9/24](project_testdata_closeout_plan_2026-09-24.md)** · [fix pass r2](project_testdata_review_fix_2026-09-24.md) · [targets 9/23](project_testdata_targets_fix_2026-09-23.md)
- vNext findings: [graceful fleet stop keeps live leases 30s](project_speedmerchants_graceful_stop_keeps_live_leases.md) → 47.K2
- [DataMutation plan](project_datamutation_plan.md) · [PerfTestData generator](project_perftestdata_generator.md) · [TDG UI redesign](project_tdg_ui_family_redesign.md)
- Installers: [install dir holds ALL artifacts](feedback_install_dir_holds_all_artifacts.md) · [purpose = unattended setup](project_vnext_installer_purpose.md) · [reuse donor installers](feedback_reuse_donor_installers.md)
- [vNext learning tour](project_vnext_learning_tour.md) — `RESUME-HERE.md`; 02+03 owed
- Speedy plan: [speedy-ui skills review](project_speedy_ui_skills_review_2026-09-09.md) · [CrewChief section plan](project_speedy_crewchief_section_plan_2026-09-12.md) · [mockup calibration](project_mockup_calibration_line.md) · [guiding document](project_speedy_guiding_document_2026-09-12.md) · [dial-up constraints](reference_speedy_dial_up_measurement_constraints.md)
- Dial: [REAL first, before gate 61](feedback_dial_up_real_first.md) · [builder design 9/13](project_dial_workload_builder_design_2026-09-13.md) · [builder v0.6 = TARGET](project_dial_builder_target_plan.md)
- Backup: [screen gate 9/22](project_backup_screen_decisions_2026-09-22.md) · [r1 verified](project_backup_restore_review_2026-09-22.md) · [abandon + rerun, no journals](feedback_simple_recovery_rerun_over_journal.md)
- Speedy testing: [interactive pages marker](reference_speedy_interactive_page_testing.md) · [Playwright enhanced nav](reference_playwright_enhanced_nav_waitforloadstate.md) · [--artifacts-path under repo](reference_artifacts_path_must_stay_under_repo.md) · [File.Move flake: InstallWithRetry](reference_file_move_overwrite_transient_access_denied.md) · [live check: loopback Testbed](reference_speedy_live_check_testbed_loopback.md)
- [Real-platform verify plan 9/23](project_speedy_real_platform_verify_2026-09-23.md) · [lab hardware](reference_lab_hardware_smvm.md)
- [Workload profiles gate 9/24](project_workload_profile_attach_gate_2026-09-24.md) — any WorkloadDefinition copy MUST copy Profiles
- Library fix list: [gate 9/24](project_library_fix_list_gate_2026-09-24.md) · [amendment r1](project_library_fix_list_amendment_r1.md)
- [Speedy video END DEMOS decisions (no disclosure, 2-3 min) + package at http://smvmtr2/speedy/](project_speedy_video_end_demos_2026-09-24.md) · [concat clips: audio shorter than video = narration runs AHEAD; apad](reference_mp4_concat_audio_gap_drift.md) · [headless Edge launcher orphans: use Browser.close](reference_headless_edge_launcher_orphans.md)
- [Speedy diagrams/video/demo: /speedy-demo skill, HowToUpdate.md in vault](project_speedy_demo_diagrams.md) · [Archify viewer behaviour VERIFIED: hover≠card, Esc keeps focus](reference_archify_viewer_behaviour_verified.md)
- [Worker channel ADR 9/25: mTLS HTTPS long-poll to coordinator, no RabbitMQ; WC/WCH rows; WCH.1 mockups](project_worker_channel_adr_2026-09-25.md)
- [Speedy build campaign 9/26: RefData>Backup>Steps>Workflows>TestAuto>Dial, one group at a time; .loop stays in repo](project_speedy_build_campaign_2026-09-26.md)
- [Stream kit: mtime grader clause always red on main after integrate](reference_stream_kit_mtime_grader_clause_breaks_on_integrate.md) — send to planned, don't rebuild
- [stream-plan 9/27: G3 Steps / G4 Workflows / G5 / G6 released, 335 tasks, page links](project_stream_plan_g2_g6_released_2026-09-27.md)
- [Stream-author takeover race: old session may still write; hash ticket/grader at claim, re-check before writes and RED sha before release](reference_stream_author_takeover_race.md)
