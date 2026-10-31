---
name: index_speedy_ui
description: "Sub-index of Speedy / TestAuto / CrewChief UI rules: layouts, UI controls, mockup gates, publishing, section gates, Speedy build approvals, warehouse"
metadata:
  type: reference
---

Moved out of MEMORY.md 2026-10-31 to keep the index under its read limit; lines kept verbatim with their original links.

- **[Steps/workloads EXCEPTION: CrewChief FULL-WIDTH workflow layout, never the 5/7 split](feedback_speedy_workflow_layout_full_width.md)**
- **[Speedy STANDING LAYOUT = CrewChief master/detail; every new panel follows it](feedback_speedy_master_detail_layout.md)** — re-laying out an audited screen discards its audit
- Speedy UI rules: [view memory = localStorage, never cookies](feedback_speedy_view_memory_localstorage.md) · [value preview reveal rule](feedback_speedy_value_preview_reveal_rule.md) · [value picker ALWAYS](feedback_value_picker_always.md) · [CrewChief LOOK AND FEEL](feedback_speedy_ui_is_crewchief_look_and_feel.md)
- [Collapsible panels = Matching scorecard rail pattern (chevron, narrow rail, localStorage)](feedback_collapsible_panels_matching_rail_pattern.md)
- UI: [mockups first](feedback_ui_mockups_before_implementing.md) · [RadzenSwitch](feedback_radzenswitch_not_selectbar.md) · [no blur-to-commit](feedback_no_blur_to_commit_ui.md) · [parity before new](feedback_ui_parity_before_new.md)
- [ANY UI design/update: ui-ux-pro-max + mockups at a gate BEFORE code](feedback_ui_port_characterise_and_uxreview.md)
- Publishing: [republish mockup GALLERY when screens change](feedback_republish_gallery_when_screens_change.md) · [republish schedule when a row is FILED](feedback_republish_on_file_not_just_on_close.md) · [TaskUpdate.html = status page](feedback_taskupdate_is_the_status_page.md) · [schedule artifact FIXED format](feedback_vnext_schedule_format.md)
- Gates: [SECTION passes only on FULL tests incl Playwright](feedback_section_close_requires_full_tests_incl_playwright.md) · [UI row closes only if Gene can VIEW + NAVIGATE it live](feedback_gate_requires_viewable_navigable_ui.md)
- [Azure central warehouse is REAL and LIVE](reference_speedy_azure_central_warehouse.md) — credential in env `SPEEDY_CENTRAL_CONNECTION` · [TWO stores: local vs central](project_vnext_two_stores_install_gate.md) · [warehouse = 127.0.0.1,14400 not localhost](reference_warehouse_loopback_127_not_localhost.md)
- **[vNext = SPEEDY; add light speed-themed humor](feedback_call_it_speedy_with_speed_humor.md)** · **[CDP = Common Data Platform, NOT Chrome DevTools; say "browser control"](reference_cdp_is_common_data_platform.md)**
- **[Speedy build: AUTO-APPROVE my recommendations, log as RDQ rows, Gene fixes at manual test](feedback_auto_approve_recommendations_speedy_build.md)**
- Standing rules (kept here): [installer dir holds ALL artifacts](feedback_install_dir_holds_all_artifacts.md) · [reuse donor installers](feedback_reuse_donor_installers.md) · [Dial: REAL first, before gate 61](feedback_dial_up_real_first.md) · [any WorkloadDefinition copy MUST copy Profiles](project_workload_profile_attach_gate_2026-09-24.md)
