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
