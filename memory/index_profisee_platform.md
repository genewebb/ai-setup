---
name: index_profisee_platform
description: Profisee platform & Connect - sub-index of MEMORY.md
metadata:
  node_type: memory
  type: reference
  originSessionId: f72b1fa1-4f0b-4455-a732-6236fcf25583
  modified: 2026-10-18T14:31:16.358Z
---

Profisee, Connect, Matching, Model Import and the corp/SMVM2 environment notes. Moved out of MEMORY.md 2026-09-10 to keep the index under its read limit; nothing was dropped.

- Corp: [dual accounts](reference_corp_dual_accounts.md) · [svc_web lockout](reference_corpltr94_svc_web_lockout.md)
- SMVM2/env: [SQL login lockout](project_smvm2_sql_login_lockout_orphan.md) · [ProfAdmin lockout](reference_smvm2_profadmin_lockout.md) · [identity drift](project_smvm2_profisee_identity_drift_chain.md) · [admin-wipe GPO](reference_corpltr94_local_admin_cleanup_gpo.md) · [port conflict](reference_corpltr94_profisee_port_conflict.md) · [lockout policy](reference_corp_domain_lockout_policy.md) · [no AD write](reference_corp_domain_no_ad_write_access.md) · [WSMAN SPN](reference_corpsql03_missing_wsman_spn.md)
- Profisee refs: [metadata DTOs](reference_profisee_metadata_dto_shapes.md) · [record paging 400](reference_profisee_gateway_record_paging_400.md) · [platform log](reference_profisee_platform_log.md) · [/health 503](reference_profisee_health_endpoint_503.md) · [Configuration.exe exit 0](reference_configuration_exe_failure_modes.md) · [Hangfire job exception](reference_hangfire_job_exception.md) · [import 500 startup](reference_import_500_gateway_startup.md) · [matching off-gateway](reference_matching_api_offgateway_baseurl.md) · [cert autorenewal](reference_testauto_cert_thumbprint_autorenewal.md) · [SynonymList delete/BaseUrl](reference_synonymlist_delete_and_baseurl.md) · [DBA = entity Code](reference_profisee_dba_is_entity_code.md)
- ConnEx: [import tokenization](project_connex_import_tokenization.md) · [template tool](project_connex_template_tool.md) · [vaultId bug](project_connex_import_vaultid_bug.md) · [inline over file](feedback_connex_artifact_inline_over_file.md) · [runAsUser escape](project_connex_runasuser_json_escape.md) · [service store & logs](reference_connex_service_store_and_logs.md) · [delete-config 403](project_connex_delete_config_403_dependency.md)
- Connect metrics: [1M proof](project_connect_metrics_proof_doc.md) · [RunProfile direction](project_connect_runprofile_direction_authority.md) · [RecordCount = key-range](reference_connex_recordcount_is_keyrange_width.md)
- Connect: [import sequence race](project_connect_import_sequence_race.md) · [PostRun cross-DB hang](project_connect_postrun_cross_database_hang.md) · [PostRun dup 8603](project_connect_postrun_duplicate_code_8603.md) · [per-page Hangfire](project_connect_perpage_hangfire_timing.md) · [ScenarioMgt vs Metrics](reference_scenariomgt_vs_metrics_subject_areas.md) · [ScenarioMgt TWO instances](reference_scenariomgt_db.md)
- Model Import: [reserved Code/Name](project_model_import_reserved_code_name.md) · [delete-side GlobalParams](project_model_import_delete_side_empty_globalparams.md) · [refdata empty body](project_model_import_refdata_empty_body.md) · [Metadata step](project_metadata_model_import.md)
- **[Matching 1M run 10000185 died on Source System 40](project_matching1m_scenario2_ss40_failure.md)** (9/9) — SS40 has no member in the SUT; 200/200 batches 207-partial, 28,200 blank-source rows inserted; SUT is CORPLTR94, not SMVM2
- Matching: **[pool offsets + clone alignment](reference_matching_pool_offsets_and_alignment.md)** (9/9) per-source maps DEAD · **[Duplicate Workflow shared CHUNKREF](project_workflow_duplicate_chunkref_sharing.md)** fixed 9/9, MERGE still OPEN · [3B/3C label bugs](project_matching_3b3c_label_and_comment_bugs.md) OPEN · [SynonymHelper loader](project_synonymhelper_loader_noop.md) · [SynonymList PUT 400](project_synonymlist_put_400_26r2.md) · [Matching100K step14](project_matching100k_step14_curl_paste_body.md)

## Matching and ModelSource (moved 2026-10-01)

- Matching: [3a step 21 hang 9/13](project_matching_3a_step21_hang_2026-09-13.md) · [UnifiedMatching metric defects](project_unified_matching_metric_defects_2026-09-13.md) · [15M/300M templates](project_matching_15m_300m_templates.md) · [PUT /Strategies saves Status=0](reference_matching_put_strategies_forces_disabled.md) · [3a target-pull](project_matching_3a_target_pull_and_quality_dial.md) · [LUBC 2219](reference_lubc_2219_is_request_validation.md) · [Gateway 400 "<" = microservice DOWN](reference_profisee_gateway_400_unexpected_character_means_microservice_down.md) · [strategy table by version](reference_profisee_matching_strategy_table_by_version.md) · [SMVM2 Matching down](project_smvm2_matching_service_down_2026-09-10.md)
- [ModelSource RetailClient has TWO shapes](reference_modelsource_retailclient_two_shapes.md)
- [UnifiedMatching PROD timing audit 9/30: wall-clock OK, chain wrong ($LastChgDTM), 3b no creates, 3c 613 Pending](project_unified_matching_prod_timing_audit_2026-09-30.md)
- [ADO 165390 Sentara first-call 2 s](project_ado_165390_sentara_first_call_2s.md)

## Moved from MEMORY.md 2026-10-18

- **[Connect: NEVER delete an entity Connect didn't create; no teardown (clean start, create, run) 10/15](feedback_connect_never_delete_entities.md)**
- [Matching lookup 400 status 2219 = no existing record (no-match), NOT error; LookupThenCreate still creates](reference_matching_lookup_2219_is_no_match.md) · [sqlcmd needs -I for Profisee table writes; backfill Monitor start marker by direct INSERT](reference_sqlcmd_quoted_identifier_profisee.md) · [Prod step config CHUNKREF decode: STRING_AGG tTestAutoScenarioConfiguration by GroupKey; batch metrics tUnifiedMatchingApiExecution](reference_prod_chunkref_config_decode_sql.md)
