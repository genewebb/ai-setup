---
name: index_infra_misc
description: Index of infrastructure, container and miscellaneous reference memories
metadata:
  type: reference
---

Moved out of MEMORY.md to keep the index under its read limit; each line keeps its original links.

- Infra: [ModelSource container](project_modelsource_container_migration.md) · [Docker+Aspire class](reference_docker_aspire_class_setup.md) · [CORPSQL03 hardware](reference_corpsql03_hardware_profile.md) · [storage layout + IFI](project_corpsql03_storage_layout.md) · [survey script](reference_machine_resource_survey_script.md) · [profisee recovery SIMPLE](project_corpsql03_profisee_recovery_simple.md) · [dpall parallel](reference_dpall_parallel_packaging.md) · [DS918 NAS](project_ds918_nas_deployment.md)
- Containers: [update can't clear limits](reference_docker_update_cannot_clear_limits.md) · [lower mem OOMs SQL](reference_docker_memory_limit_lowering_oom.md) · [wsl --shutdown wedges](reference_wsl_shutdown_wedges_docker_desktop.md) · [Rancher switch](reference_rancher_desktop_switch.md)
- Misc refs: [NuGet feed org-scoped](reference_profisee_nuget_feed_org_scoped.md) · [PS script gotchas](reference_powershell_script_contract_gotchas.md) · [dynamic T-SQL](reference_dynamic_tsql_gotchas.md) · [ExtensionData THROWS](reference_newtonsoft_extensiondata_vs_missingmember.md) · [BlazorMonaco](reference_blazormonaco_integration_gotchas.md) · [PPTX toolchain](reference_pptx_deck_toolchain.md) · [metrics folder](reference_metrics_folder.md) · [perfDashboard](project_perfdashboard.md) · [Obsidian memory](project_obsidian_memory_system.md) · [PS7 redirect encoding](reference_powershell_native_exe_redirect_encoding.md) · [no venvs on D:](reference_no_venvs_on_nas_d_drive.md) · [Windows OCR](reference_windows_ocr_without_ghostscript.md) · [Radzen Light+Text invisible](reference_radzen_light_text_button_invisible.md) · [archify diagrams](reference_archify_diagram_skill.md)

## Shell, PowerShell, .NET/Blazor and infra refs (moved 2026-10-01)

- [Documented security property never tested reads as measured](reference_documented_security_property_never_tested.md)
- Shell gotchas: [backslash escapes in heredocs](reference_backslash_escapes_become_control_bytes.md) · [Git Bash grep CR count lies](reference_gitbash_grep_cr_count_lies.md) · [python print CRLF breaks bash loops](reference_python_print_crlf_breaks_bash_loops.md) · [[switch] param shadows local var; $Home read-only](reference_powershell_switch_param_shadows_local_var.md) · [Copy-Item preserves mtime](reference_copy_item_preserves_mtime_breaks_counterfactual.md) · [PS7 -MaximumRedirection sticks to -WebSession](reference_pwsh_webrequestsession_stores_maxredirection.md)
- [Rancher Desktop autoStart = LOGIN not boot](reference_rancher_desktop_autostart_is_login_scoped.md)
- [Radzen grid: unsized column collapses to zero](reference_radzen_datagrid_unsized_column_collapses.md)
- Other projects: [CDP SqlBulkCopy](project_cdp_sqlbulkcopy_regression.md) · [governance review](governance_project_review.md) · [swarm pipeline](project_swarm_pipeline.md) · [SM SQL refactor](speed-merchants-sql-refactor.md)
- [CORPSQL03 C: full 9/28: 329 GB ERRORLOG from 9002 spam; log backups failing 3013 since 9/26 05:45](project_corpsql03_c_drive_full_2026-09-28.md)
- [On-prem perf rack 9/28: Option A 9x1U rack vs Option B CORPSQL03 duplicate, Lucid PerfRack2](project_onprem_perf_rack_options_2026-09-28.md)
- Blazor: [Dispose must not resolve services](reference_blazor_dispose_must_not_resolve_services.md) · [Razor string param needs @; .card on popover](reference_razor_string_param_needs_at_and_card_popover.md)
- [.NET 10 midpoint rounding: {0:0} away, N0/F0 even](reference_dotnet_format_midpoint_rounding.md)
- [PS single-pair array flattens: $p[0] is a CHAR, corrupted a file](reference_powershell_single_pair_array_flattens.md) — use @( ,@(a,b) ); restore via transcript + re-corrupt byte-exact check
- [SMVMTR1 CIM from laptop: WinRM Kerberos fails, use -Protocol Dcom session](reference_smvmtr1_cim_needs_dcom.md)
- [pwsh RAM % via GC (no WMI) + claude.exe process tree](reference_pwsh_ram_pct_and_claude_process_tree.md)
- [Claude CLI: -n = name only, --bg/attach, budget -p only, mod command.run untested](reference_claude_cli_session_flags.md)
- [AI setup moving work-ai -> S:\AIWork](project_aiwork_move_to_s_drive.md) — .claude.json holds a plain-text PAT, never copy it
- [Write-VaultFile: binaries need image/png or octet-stream, text/* corrupts](reference_write_vaultfile_binary_content_type.md) — hash the Q: file after every binary put
- [Teams paste = inline-styled HTML (Edge, Ctrl+A/C) + chart PNG; confirmed 10/10](reference_teams_paste_inline_html.md)
- [Prod speedmerchants -> local via BACPAC: D:\PowershellScripts\Restore-ProdSpeedmerchantsLocal.ps1; SqlPackage >=170.5.96, 6 traps](reference_prod_speedmerchants_to_local_bacpac.md)
