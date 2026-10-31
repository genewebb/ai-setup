Index of memories: one short line per entry, with detail in the files. Topic entries are in the sub-indexes below. Rules that apply in every session stay here.

## Sub-indexes (open the one that matches the task)
- [Profisee / Connect / Matching / Monitor](index_profisee_platform.md) · [TestAuto](index_testauto.md) · [CrewChief](index_crewchief.md) · [Speedy/TestAuto UI rules](index_speedy_ui.md)
- [Claude harness, ai-setup, profile, machine config](index_claude_harness.md) · [Infra, shell, misc](index_infra_misc.md) · [Stream kit + host](index_stream_host_kit.md)
- [vNext/Speedy plan + design](index_vnext_plan_design.md) · [Speedy requirements + trackers](index_speedy_requirements.md)

## How Gene wants me to work
- [Voice = caveman + Truth format](feedback_voice_caveman_plus_truth_format.md) · **[EVERY decision = AskUserQuestion + recommendation](feedback_questions_via_askuserquestion.md)** · [prompts: FULL paths + Suggestion block](feedback_prompts_full_paths_with_suggestions.md)
- Workstyle: [do it right, never patch](feedback_do_it_right_not_a_patch.md) · [plain English + before/after](feedback_explain_plain_english_with_example.md) · [verify, no guessing](feedback_verify_no_guessing.md) · [scope discipline](feedback_scope_discipline.md) · [implement autonomously](feedback_implement_autonomously.md) · [review whole subsystem](feedback_review_whole_subsystem_not_serially.md) · [full script every iteration](feedback_full_script_every_iteration.md) · [user rebuilds app](feedback_user_rebuilds_app.md)
- [Gene doing steps by hand: ONE step per reply](feedback_one_step_at_a_time_when_troubleshooting.md) · [Asked "what is the command" = command only, run nothing](feedback_command_question_answer_only.md)
- [Long runs self-drive with /loop](feedback_always_make_long_runs_unattended.md) · [run independent tasks in parallel](feedback_run_parallel_when_possible.md) · [Copy before probing; NEVER git checkout to undo](feedback_copy_before_probe_never_git_checkout.md)
- [Testing: integration over unit](feedback_testing_philosophy_integration_over_unit.md) · [Libraries: FREE OSS only (MIT/Apache)](feedback_free_oss_only_no_revenue_gated_libs.md)
- Code: [centralize constants](feedback_centralize_constants.md) · [207 not success](feedback_207_not_success.md) · [record codes from response](feedback_recordcode_from_response.md) · [reuse PathAndQueryBuilder](feedback_rest_reuse_path_query_utility.md) · [reuse config sections](feedback_reuse_existing_config_sections.md) · [atomic tests](feedback_tests_must_be_atomic.md) · [no outside fixtures](feedback_unit_tests_no_outside_artifacts.md) · [tech stack](project_tech_stack.md) · [DI factory lambda hides missing dep](reference_factory_lambda_hides_missing_di_dependency.md) · [read path that WRITES fails under load](reference_read_path_that_writes_fails_under_load.md)

## Git and safety (always apply)
- Git: [commits OK in speedmerchants, NEVER in speed-merchants](feedback_no_commits.md) · **[shared ADO repos: never commit/push main, branch + PR](feedback_no_direct_commits_to_main_pr_only.md)** · [worktrees allowed, must integrate](feedback_worktrees_allowed_must_integrate.md) · [dual accounts, no gh](project_git_config.md) · [GCM: pin user in URL](reference_gcm_two_github_accounts_pin_username.md) · [status vs diff](reference_git_status_vs_diff_no_head.md) · [no binary check-ins](feedback_no_binary_checkins.md)
- **[Test keys: never warn about exposure or rotation](feedback_test_keys_no_warnings.md)** · **[Profisee 401 body echoes the API key: never print it](reference_profisee_gateway_401_echoes_api_key.md)** · **[Connect SC import echoes Snowflake private key](reference_connect_sc_import_echoes_snowflake_private_key.md)**
- **Connect: NEVER delete an entity Connect didn't create** (see [index_profisee_platform](index_profisee_platform.md)) · [CORPLTR94 runs BOTH Profisee installs, both required](project_local_two_profisee_installs_required.md)
- **[ai-setup rollout = prof setup reload / prof setup push / prof streams update](feedback_ai_setup_rollout_via_prof.md)** · [ai-setup git flow: work/<change> branch, both clones clean first](project_ai_setup_branch_workflow_2026-10-18.md)

## Environment
- **[Laptop shell = CORP\agenewe, not genewe](reference_corp_dual_accounts.md)** · [runs Claude elevated by choice](feedback_runs_elevated_by_choice.md) · [Key repos](project_repos.md) · [workspace start](project_workspace_start_convention.md)
- [vNext = SPEEDY, light speed humor](feedback_call_it_speedy_with_speed_humor.md) · [CDP = Common Data Platform, not Chrome DevTools](reference_cdp_is_common_data_platform.md)

## Active work (newest first; full status in each file)
- [Matching scorecard wizard 10/29: built, uncommitted](project_matching_scorecard_wizard_2026-10-29.md) · [Connect test board 10/30](project_connect_test_board_2026-10-30.md) · [ModelSource split per size 10/28](project_modelsource_split_per_size_dbs_2026-10-28.md)
- [Post-run collection slow: 3c records matching never touches](reference_postrun_collection_slow_dns_outage_2026-10-29.md) · [manual monitor marker insert](reference_manual_monitor_marker_insert.md)
- [logpull v1.2 10/26](project_logpull_v12_gui_2026-10-26.md) · [ADO 166723 DATAS GC re-run](project_ado_166723_26r3_perf_datas_gc.md) · [CrewChief remove instance 10/21](project_crewchief_configure_remove_instance_2026-10-21.md)
- [prof setup share 10/23](project_prof_share_design_2026-10-23.md) · [profile load NAS fix 10/27](reference_profile_load_nas_clearseq.md)
