---
name: index_claude_harness
description: "Claude Code harness, skills & session rules - sub-index of MEMORY.md"
metadata: 
  node_type: memory
  type: reference
  originSessionId: 36fb0eef-6e00-4263-8243-c6afdfbf3c20
  modified: 2026-09-14T15:05:46.090Z
---

Hooks, permissions, statusline, skills maintenance and session conventions. Moved out of MEMORY.md 2026-09-10 to keep the index under its read limit; nothing was dropped.

- Claude/harness: [SessionEnd "Hook cancelled" = two 1.5s budgets](reference_sessionend_hook_1_5s_budget.md) · [statusline = quota, no dollars](feedback_statusline_quota_not_dollars.md) · [quota via /api/oauth/usage](reference_statusline_per_model_quota.md) · [hook activation](reference_claude_hook_activation.md) · [hook output channels](reference_claude_hook_output_channels.md) · [GateGuard: 4 facts, once per file](reference_gateguard_hook.md) · [permissions sync](reference_permissions_sync.md) · [tier precedence](reference_permission_tier_precedence.md) · [drift checker](reference_permissions_drift_checker.md) · [path-form gotcha](reference_path_form_gotcha.md) · [Workflow parallelizes](feedback_workflow_parallelizes_agents.md) · [AgentTool rule](reference_agenttool_rule_in_binary.md) · [prompt cost](reference_prompt_cost_analysis.md) · [verify MCP first](feedback_verify_mcp_before_unavailable.md) · [ECC](project_ecc_adoption.md) · [skills installer](project_agent_skills_installer.md) · [AI toolkit](project_ai_toolkit_setup.md) · [remember plugin](project_remember_plugin_install.md) · [caveman plugin](project_caveman_plugin_install.md) · [auto-mode stripped Bash(*)](reference_auto_mode_setup_stripped_bash_wildcard.md)
- Skills: [UI/UX Pro Max pack: vault-backed, design->uipro-design, no `uipro update`](reference_uipro_skill_pack_vault_install.md) · [profile system](project_skill_profile_system.md) · [override two speeds](reference_skill_override_two_speeds.md) · [size×invocations](reference_skill_cost_is_size_times_invocations.md)
- Session rules: [autoCompactWindow 50%](reference_autocompact_window_setting.md) · [compact at 50% at an iteration boundary](feedback_compact_at_50_percent_iteration_boundary.md) · [update live schedule artifact at every dispatch/close](feedback_iteration_close_print_remaining_tasks.md) · [scratch dir C:\temp](feedback_scratch_dir_is_c_temp.md) · [max 4000-char responses](feedback_max_response_4000_chars.md) · [publish deliverables as artifacts](feedback_publish_artifacts_and_archive.md) · [review pages need a readable pick channel](feedback_review_pages_need_readable_pick_channel.md)

## Harness refs (moved 2026-10-01)

- [Skill linker needs mklink /D, not /J](reference_skill_linker_needs_symlinks_not_junctions.md) — linker RETIRED 10/1 (Install-AIMachine copies)
- [Claude needs-input flash in WezTerm = preferredNotifChannel terminal_bell + visual_bell; hooks can't emit BEL](reference_claude_wezterm_attention_bell.md)
- [destructive-path-guard "(/c)" prompt = cmd switch false positive; hook ask beats allow; C:\tmp\Patch-DestructivePathGuard.ps1](reference_destructive_path_guard_cmd_switch_false_positive.md)
