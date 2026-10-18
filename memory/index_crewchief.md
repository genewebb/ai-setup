---
name: index-crewchief
description: "Sub-index of every CrewChief memory (core, UI, secrets, values, library, steps, config, content, DB-Ops, packaging, remote, Run-As, docs, ConnEx import) — read when the task touches CrewChief"
metadata: 
  node_type: memory
  type: reference
  originSessionId: acc1f014-7b40-4f0e-b985-81edf62b4a29
  modified: 2026-10-18T14:31:13.469Z
---

- Core: [standalone](project_crewchief_standalone.md) · [activity merge](project_crewchief_activity_merge.md) · [arch review 7/17](project_crewchief_review_2026-07-17.md) no-auth RCE open · [duplication audit](project_crewchief_duplication_audit.md) · [vs AutomationUtility](project_crewchief_vs_automationutility.md)
- UI: [Connect Import UX](project_crewchief_connect_import_ux.md) · [conventions](project_crewchief_ui_conventions_2026-07.md) · [sticky filters](reference_crewchief_sticky_filters.md) · [raw JSON panes](project_crewchief_raw_json_panes.md) · [run monitor](project_crewchief_run_monitor_2026-07-24.md) · [stale CSS bust](project_crewchief_stale_css_cache_bust.md) · [badge bugs](project_crewchief_capability_badge_invalidation.md) · [SecretRevealToggle desync](project_secretrevealtoggle_grantvalid_desync.md) OPEN
- Secrets: [delete](project_crewchief_secrets_delete.md) · [CLI store delete](project_crewchief_secrets_store_delete_cli.md) · [two-tier sealed](project_crewchief_secrets_shipped.md) · [tier rename](project_crewchief_tier_rename.md) · [secrets.local.json gone](project_crewchief_secrets_local_json_eliminated.md) · [sample templates](project_crewchief_sample_secrets_template.md) · [pickers on MOST fields](project_crewchief_secret_picker_convenience_only.md)
- Values: [Builder value source](project_crewchief_value_builder.md) · [CLU wizard + value card](project_crewchief_clu_wizard_and_step_param_value_card.md) · [value card 8/25](project_crewchief_value_card_2026-08-25.md) · [picker unification 9/1](project_crewchief_value_picker_unification.md)
- Library: [folders](project_crewchief_folders.md) SHIPPED 9/1 · [bulk tagging](project_crewchief_bulk_tagging.md) · [token filters](project_crewchief_token_filters.md) · [filter rows + composer](project_crewchief_filter_rows_composer.md) · [8-item batch 8/31](project_crewchief_enhancements_2026-08-31.md) · [preflight two-hop token leak](project_crewchief_preflight_twohop_token_leak.md) FIXED
- Steps: [pool protection](project_crewchief_builtin_pool_protection.md) · [StepType factory dup](project_crewchief_steptype_factory_duplicated.md) · [coverage assertions](project_crewchief_steptype_coverage_assertions.md) · [WebSiteStep](project_crewchief_website_step.md) · [delete IIS gotchas](project_crewchief_website_delete_iis_gotchas.md) · [HTTP/Curl split](project_crewchief_http_curl_split.md) · [param-in-param](project_crewchief_param_in_param.md) · [bare param guard](project_crewchief_bare_param_name_guard.md) · [workload merge](project_crewchief_workload_merge.md) · [backup/restore](project_crewchief_backup_restore.md)
- Config/refdata: [custom actions](project_crewchief_configure_custom_actions.md) · [switches](project_crewchief_configure_switches.md) · [reference pickers](project_crewchief_reference_pickers.md) · [HTTPS cert-only](project_crewchief_https_certonly_and_iisreset_rename.md) · [LogonType clobber](project_crewchief_configure_connect_logontype_clobber.md) · [CLI fixes](project_crewchief_cli_fixes.md) · [backup location](project_crewchief_backup_location_refdata_authority.md)
- Content: [smart seed](project_crewchief_smart_seed.md) · [selective install](project_crewchief_templates_selective_install.md) · [seeder date collision](project_crewchief_seeder_date_collision.md)
- DB-Ops: [DropDB guard](project_crewchief_dropdb_connstring_guard.md) · [rename/relocate](project_crewchief_dbops_rename_relocate.md) · [logical-rename case](project_crewchief_relocate_logical_rename_case.md) · [named-instance](project_crewchief_named_instance_support.md)
- Packaging: [Inno installer](project_crewchief_installer_plan.md) · [share publish](reference_package_share_publish.md) · [ADO build download](project_crewchief_ado_build_download.md) · [TestAuto→CrewChief export wizard](project_crewchief_export_wizard.md) · [Reset workloads](project_crewchief_reset_workloads_plan.md)
- Remote: [box-prep transport](project_crewchief_remote_boxprep_transport.md) · [setup script](project_crewchief_remote_setup_script.md) · [/setup verification](project_crewchief_setup_verification.md) · [share credentials](project_crewchief_share_credentials.md) · [CredSSP](project_crewchief_credssp_diagnosis.md)
- Run-As: [credentialed remote ops](project_crewchief_credentialed_remote_ops.md) · [direct logon](project_crewchief_local_runas_direct_logon.md) · [1024-char cmdline](project_crewchief_localrunas_cmdline_1024.md) · [inheritance carve-out](project_crewchief_workload_runas_inheritance_carveout.md) · [account mismatch](project_crewchief_localrunas_account_mismatch.md) OPEN
- Docs: [credential audit](project_crewchief_docs_credential_audit_2026-07-25.md) · [full audit 8/7](project_crewchief_docs_full_audit_2026-08-07.md)
- ConnEx import: [THREE bugs](project_crewchief_connex_import_three_bugs.md) · [live tests](project_crewchief_connex_import_tests.md) · [apikey 401 + globals](project_crewchief_connect_import_apikey_globals.md)

## Moved from MEMORY.md 2026-10-01

- [CrewChief: Steps and Workloads have SEPARATE folder lists](project_crewchief_separate_folder_lists.md) · [Run disabled = single run slot held](reference_crewchief_run_disabled_single_slot_remote_installs.md)
- [CrewChief remaining port approved 9/23](project_crewchief_remaining_port_2026-09-23.md) · [bundle import + workload Run As 9/24](project_crewchief_bundle_import_and_workload_runas.md) · [metric/version/scenario profiles 9/24 + TRACKER MP-0..12](project_metric_version_scenario_profiles_2026-09-24.md)

## Moved from MEMORY.md 2026-10-18

- **[CrewChief connect restructure 10/13: `connect` folder, PData* entities; generator -Environment Local|SMVMTR1 (SMVMTR1 set deployed, secrets SMVMTR1_connect_crewchief.json built); prod TestAuto writes blocked on ScenarioMgt key](project_crewchief_connect_restructure_2026-10-13.md)**
- **[CrewChief secrets -> reference data 10/15: only creds/keys/thumbprints secret; reference-kv parent folders; CrewChief folder types + configuration-bindings + builtIn/description markers + list/edit screen (uncommitted); SMVMTR1 non-connect workloads deleted (backed up); slim secrets built, import after rebuild](project_crewchief_secrets_to_reference_data_2026-10-15.md)**
