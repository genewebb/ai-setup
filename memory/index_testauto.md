---
name: index_testauto
description: "Index of TestAuto memories: HTTPS/boot, packaging, list-page and project notes, gotchas, test campaigns"
metadata:
  node_type: memory
  type: reference
  originSessionId: f72b1fa1-4f0b-4455-a732-6236fcf25583
  modified: 2026-10-18T14:31:15.017Z
---

Moved out of MEMORY.md to keep the index under its read limit; each line keeps its original links.

- TestAuto HTTPS/boot: [localhost mismatch](reference_testauto_https_localhost_name_mismatch.md) · [7009 timeout](reference_testauto_service_boot_7009_timeout.md) · [Entra P2P lockout](reference_testauto_entra_p2p_cert_lockout.md) · [degraded Hangfire DI](reference_testauto_degraded_mode_hangfire_di.md)
- TestAuto packaging: [SQL 18452](reference_testauto_local_service_account_18452.md) · [service install](project_testauto_service_install_plan.md) · [unified versioning](reference_version_scheme_unified.md) · [secrets persistence](project_testauto_secrets_persistence_diagnosis.md) · [Production Sync](project_testauto_production_sync_plan.md) · [linux container](project_testauto_linux_container_plan.md)
- TestAuto: [list page N+1](project_list_page_nplus1_parallelization.md) · [SplitShared v3](project_splitshared_v3.md) · [WorkloadExecution cleanup](project_workloadexecution_cleanup.md) · [Blazor Web App](project_blazor_webapp_migration.md) · [.NET 10](project_net10_profisee_upgrade.md) · [secrets middleware](project_secrets_bootstrap_middleware_not_wired.md) · [microservice startup](project_microservice_startup_analysis_final.md) · [file-reference retirement](project_file_reference_retirement.md) · [logging migration](project_logging_migration.md) · [Plugins\ stale](project_testauto_plugins_folder_not_refreshed_by_build.md) · [bare HTTP = stale build](reference_bare_http_error_means_stale_build.md) · [orchestration seams](reference_testauto_orchestration_seams.md)
- TestAuto gotchas: [recordsAreSameShape](reference_recordsaresameshape_first_record_contract.md) · [ScenarioDataDisplay 4000](reference_scenariodatadisplay_4000_ceiling.md) · [chunk trim](project_chunk_boundary_whitespace_trim.md) · [GetRecords caps 50](project_getrecords_pagesize_truncation.md) · [step resolution skipped](project_step_resolution_skipped_empty_detail_codes.md) · [workflow copy dup save](project_workflow_copy_duplicate_save_bug.md) · [config token prefix](reference_scenario_config_token_prefix.md) · [JSON case audit](reference_json_case_insensitivity_audit.md) · [error-logging audit](reference_rest_connect_error_logging_audit.md) · [PS 5.1 Latin-1](project_ps51_latin1_body_encoding.md) · [CurlExecutor port flaky](reference_curlexecutor_test_port_flakiness.md)
- Tests: [integration fix campaign](project_integration_test_fix_campaign.md) · [test-loop auto-approve](project_test_loop_autoapprove_hook.md) · [CRUDTests env swap](project_profiseecrudtests_env_swap.md) · [test output path](reference_speedmerchants_cursor_testoutput_path.md)

## Moved from MEMORY.md 2026-10-18

- [TestAuto metric run purge 10/8: backend + wizard/orphans pages BUILT, uncommitted; areas from WorkArea table](project_testauto_metric_run_purge_2026-10-07.md) — Rev 12 tree wizard + Clean up sequence (orphans, empty versions, summary; purge never removes versions) BUILT 10/10 (unit green, UI unviewed); earlier: CLOSED 10/9 after rev 9; open only on request: req doc amendment revs 5-9, integration tests unrun, 2 perf optimisations
- [TestAuto exec metrics catalog Claude Doc 10/10 (Matching/CRUD/Connect + scorecard mockup, illustrative values)](reference_testauto_metrics_catalog_doc.md)
- [TestAuto Monitor step COMPLETE but no row = silent NSB send fail; check nsb_log + MonitorDB catalog](reference_testauto_monitor_send_silent_fail.md) · [SMVMTR3 stuck job: read Hangfire testautojobs.State via sqlcmd (no Seq)](reference_smvmtr3_hangfire_job_diagnosis.md) · [SMVMTR2 step errors = C:\Deploy\TestAuto\web\LogFiles (not tLogging/Seq); SQL via ODBC ServerSPN](reference_smvmtr2_testauto_logs_and_sql.md)

## Moved from MEMORY.md 2026-10-31 (lines verbatim)

- [ADO 166723 26R3 perf regression: Josh wants Batch Record Read re-run with DOTNET_GCDynamicAdaptationMode=0 (DATAS off); 26.3 = net10 Server GC](project_ado_166723_26r3_perf_datas_gc.md)
- **[Matching scorecard WIZARD 10/29: mockup v15 approved, BUILT uncommitted, unit tests pass, SQL 21/22 RUN on prod 10/29; port skill scorecard-wizard](project_matching_scorecard_wizard_2026-10-29.md)**
- **[TestAuto Version Compare charts 10/21: mockup gate, decisions, Radzen 7.1.7 -> 12.1.5 upgrade chosen, offline copy C:\tmp\chart; 10/22 error rates BUILT as table columns only](project_testauto_version_compare_charts_2026-10-21.md)**
- TestAuto metric run purge 10/10 (rev 12 BUILT, uncommitted) + metrics catalog doc: see [index_testauto](index_testauto.md)
- [Bulk delete UI: groups (entity+reason+totals) not rows; one subject area; parent filter + tree](feedback_bulk_delete_ui_groups_not_rows.md)
- **[METRICS schema gaps 8609 = stop sending columns (hide in detail class), NEVER add to metrics model](feedback_metric_schema_gaps_stop_sending_not_add.md)**
- [speed-merchants integration tests HUNG on CORPLTR94 10/10 before seeding (suspect AssemblyInitialize CDP/NSB); probe with timeout 240 first](reference_speedmerchants_integration_tests_hang_corpltr94.md)
- **[Snapshot step stuck Running = missing run-profile row (REST 207 / 8617); Hangfire retries 10x writing orphan rows; WorkloadExecution never Failed; Hangfire DB recreate kills retry](reference_snapshot_step_stuck_missing_run_profile.md)**
