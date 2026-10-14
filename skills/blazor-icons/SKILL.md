---
name: blazor-icons
description: >
  Material Symbols icon whitelist and Bootstrap→Material legacy name mapping for Radzen Blazor. Use when adding icons to
  Blazor UI, choosing which icon to use, looking up approved icon names,
  using Radzen.Icon or the Icon component, reviewing icon usage in .razor files,
  mapping old Bootstrap/Open Iconic names (pencil-square, gear, clock-history, speedometer, graph, question-circle) to their Material equivalents,
  or diagnosing an icon that renders as literal text instead of a glyph.
---

# Approved Icons

> **Purpose:**  
> Defines the **approved Material icons** for use across TestAuto.Web.  
> Icons must be from the **Material Symbols** set used by Radzen.Blazor (v7.1.7).  
> Unsupported Bootstrap icons (e.g. `diagram-3`, `pencil-square`, `box-arrow-up-right`) **must not be used**.

---

## Navigation & General
| Icon Name | Description |
|---|----|
| `home` | Main dashboard or home page |
| `dashboard` | General control panel / metrics view |
| `menu` | Hamburger / navigation toggle |
| `menu_open` | Expanded state of a collapsible nav/index panel — pairs with `menu` (`Components/Help/HelpLayout.razor:14`: `<Icon Name="@(_indexCollapsed ? "menu" : "menu_open")" />`) |
| `settings` | Configuration or preferences |
| `help` | Help / documentation |
| `info` | Information message or section |
| `open_in_new` | External link indicator (replaces `box-arrow-up-right`) |
| `link` | Hyperlink or external connection |
| `logout` | Sign-out / exit action |
| `person` | User profile |
| `account_circle` | Signed-in user avatar in the top-bar user menu (`Components/Layout/MainLayout.razor:27`) |
| `manage_accounts` | Admin or account management |
| `share` | Share or distribute |

---

## Actions & CRUD
| Icon Name | Description |
|---|----|
| `add` | Bare plus — inline "add row / add item" affordances. The most common add glyph in production; prefer it over `add_circle` for dense rows and toolbar buttons |
| `add_circle` | Add or create new item (filled circle variant) |
| `remove_circle` | Remove / delete item |
| `edit` | Edit record or configuration (replaces `pencil-square`) |
| `edit_note` | Edit document / metadata |
| `delete` | Delete or trash |
| `save` | Save changes |
| `content_copy` | Copy content |
| `content_paste` | Paste content |
| `refresh` | Reload or refresh data |
| `play_circle` | Start or run process |
| `pause_circle` | Pause process |
| `stop_circle` | Stop process |
| `bolt` | Quick action / automation trigger |
| `restart_alt` | Restart operation |
| `check_circle` | Approve / confirm / success state |
| `cancel` | Cancel or close dialog |
| `close` | Generic close button |
| `check` | Simple checkmark / inline confirmation |
| `delete_forever` | Permanent / hard delete (no undo) |
| `file_upload` | Upload file action |
| `fact_check` | Validate, audit, or review checklist |
| `arrow_upward` | Move item up / scroll to top |
| `vertical_align_bottom` | Align or move to bottom |
| `vertical_align_top` | Align or move to top |

---

## Metrics & Monitoring
| Icon Name | Description |
|---|----|
| `favorite` | Health / heartbeat / system OK indicator |
| `monitor_heart` | Healthcheck or diagnostic monitor |
| `show_chart` | Metrics, graphs, or performance visualization |
| `analytics` | Detailed analytics view |
| `bar_chart` | Charts and numerical insights |
| `timeline` | Sequential time-based data |
| `schedule` | Time or recent activity indicator |
| `history` | Historical runs or audit log |
| `query_stats` | Query performance indicator |
| `speed` | Throughput or performance speed gauge |
| `percent` | Percentage-based metric or ratio |

---

## Workflow & Integration
| Icon Name | Description |
|---|----|
| `account_tree` | Workflow / branching process (replaces `diagram-3`) |
| `schema` | Logical diagram / scenario flow |
| `hub` | Central hub or orchestrator |
| `device_hub` | Network / data flow visual |
| `integration_instructions` | Integration points or connectors |
| `api` | API integration |
| `extension` | Plugin or custom module |
| `build_circle` | Build or pipeline job |
| `data_object` | Entity / data object |
| `model_training` | AI/ML or training workflow indicator |
| `settings_applications` | Application-level settings |
| `settings_ethernet` | Network or connection-level settings |
| `terminal` | CLI, shell, or console output |
| `tune` | Fine-tune parameters or filter controls |
| `rocket_launch` | Launch, deploy, or kickoff action |

---

## Data, Scenarios & Records
| Icon Name | Description |
|---|----|
| `table_chart` | Data table or results grid |
| `storage` | Database or persistence |
| `folder` | Scenario grouping |
| `dataset` | Dataset / data source |
| `description` | File or configuration document |
| `grid_view` | Grid layout or structured view |
| `list_alt` | List view or summary |
| `view_list` | Alternate list layout |
| `import_export` | Data import/export |
| `upload_file` | File upload |
| `download` | File download |
| `cloud_upload` | Upload to cloud |
| `cloud_download` | Download from cloud |
| `folder_open` | Open or expanded folder |
| `format_list_bulleted` | Bulleted list display |
| `list` | Simple list view |
| `view_module` | Module/card grid layout |

---

## Diagnostics & Alerts
| Icon Name | Description |
|---|----|
| `warning` | Warning / risk indicator |
| `error` | Error or failure |
| `error_outline` | Non-critical error |
| `report_problem` | Report or alert |
| `notifications` | Notification bell |
| `bug_report` | Debug or defect tracking |
| `visibility` | Show details |
| `visibility_off` | Hide details |
| `lock` | Secure / protected |
| `lock_open` | Unlocked / exposed |
| `key` | Credentials / secret access |

---

## Controls & Navigation
| Icon Name | Description |
|---|----|
| `keyboard_arrow_up` | Move up |
| `keyboard_arrow_down` | Move down |
| `arrow_forward` | Next or continue |
| `arrow_back` | Previous or back |
| `arrow_right_alt` | Proceed or flow to next |
| `swap_vert` | Reorder / move |
| `unfold_more` | Expand |
| `unfold_less` | Collapse |
| `filter_alt` | Filter options |
| `sort` | Sort data |
| `search` | Search or query input |

---

## Miscellaneous Utility
| Icon Name | Description |
|---|----|
| `inbox` | Empty state / no items placeholder |
| `help_center` | Help or support module |
| `flag` | Mark for review |
| `label` | Tag or categorization |
| `map` | Geographic or layout context |
| `history_toggle_off` | Offline / inactive run |
| `visibility` | Show content |
| `visibility_off` | Hide content |
| `calendar_month` | Date picker or calendar reference |
| `camera` | Screenshot, capture, or image action |
| `event_available` | Scheduled event confirmed |
| `memory` | Memory usage or system resource |
| `newspaper` | News feed or content updates |
| `star` | Favorite, rating, or highlight |

---

## Also in production use — verified by scan

The tables above were hand-curated and had drifted behind the code. The names below are all
**real Material Symbols already rendering in `TestAuto.Web/**/*.razor`**, and are approved on the
same footing as everything above.

> Derived by extracting every literal `Icon="…"` / `<Icon Name="…">` value from
> `TestAuto.Web/**/*.razor` and diffing against this document on **2026-07-27**. Icon usage moves
> faster than this file — re-run that extraction rather than trusting this list to be complete.

| Icon Name | Description |
|---|---|
| `arrow_downward` | Move item down / sort descending |
| `autorenew` | Auto-refresh or in-progress spinner |
| `backup` | Backup / snapshot action |
| `cached` | Cache state or cache-clear action |
| `check_box` | Explicit checkbox state |
| `checklist` | Multi-item checklist / preflight |
| `chevron_left` / `chevron_right` | Pager and carousel navigation |
| `compare_arrows` | Diff / compare two things |
| `delete_sweep` | Bulk delete / clear all |
| `done_all` | All items completed |
| `file_download` | Download a specific file (contrast `download`) |
| `filter_alt_off` | Clear active filters — pairs with `filter_alt` |
| `folder_off` | Missing / unavailable folder |
| `hourglass_empty` / `hourglass_top` | Waiting / queued state |
| `input` / `output` | Inbound vs outbound data direction |
| `manage_search` | Advanced search or query builder |
| `more_horiz` | Overflow menu |
| `note_add` | Create a new document / config |
| `open_in_full` | Expand to full screen |
| `play_arrow` | Bare play — contrast the circled `play_circle` |
| `rocket` | Launch / kickoff (bare variant of `rocket_launch`) |
| `save_as` | Save a copy under a new name |
| `stop` | Bare stop — contrast the circled `stop_circle` |
| `update` | Update / apply changes |
| `upload` | Upload action (contrast `file_upload` / `upload_file`) |
| `verified` | Verified / trusted state |
| `warning_amber` | Softer warning variant |

### Map targets that were missing from the whitelist

These are **values** in the `LegacyToMaterial` table below, so they are reachable through the
translation layer and are valid to use directly. They were absent from the tables above:

| Icon Name | Reached via | Description |
|---|---|---|
| `sync_alt` | `arrow-left-right` | Bidirectional sync / transfer |
| `code` | `code-slash` | Source code / raw JSON view |
| `build` | `tools` | Build or maintenance action |
| `inventory_2` | `inbox` | Empty-state box. **Note the collision**: `inbox` is listed as an approved Material name in "Miscellaneous Utility" above, but `Icon.razor.cs` maps `inbox` → `inventory_2` before rendering, so `<Icon Name="inbox" />` renders the `inventory_2` glyph. Write `inventory_2` when you mean it. |

---

## Legacy Bootstrap Name Mapping

`Icon.razor.cs` includes a translation layer that converts old Bootstrap/Open Iconic names to their Material Symbols equivalents. These legacy names are no longer used in new code but may still appear in older `.razor` files — the mapping layer prevents runtime errors during migration.

| Legacy Name (Bootstrap/Open Iconic) | Material Symbols Equivalent |
|---|---|
| `heart` | `favorite` |
| `graph-up` | `show_chart` |
| `graph` | `show_chart` |
| `lightning` | `bolt` |
| `clock` | `schedule` |
| `clock-history` | `schedule` |
| `list-ul` | `format_list_bulleted` |
| `file-earmark-text` | `description` |
| `speedometer` | `speed` |
| `speedometer2` | `speed` |
| `gear` | `settings` |
| `pencil-square` | `edit` |
| `cloud-upload` | `cloud_upload` |
| `arrow-left-right` | `sync_alt` |
| `grid-3x3-gap` | `grid_view` |
| `code-slash` | `code` |
| `question-circle` | `help` |
| `tools` | `build` |
| `monitor` | `monitor_heart` |
| `percent` | `percent` |
| `inbox` | `inventory_2` |
| `table` | `table_chart` |

The lookup is case-insensitive (`StringComparer.OrdinalIgnoreCase`); names containing `_` are assumed to already be Material names and bypass the map. Legacy names **not** in this table (e.g. `trash`, `diagram-3`, `box-arrow-up-right`, `pie-chart`) are NOT mapped — they pass through as-is and hit the failure mode below.

> **FAILURE MODE — literal text rendering**: When an invalid or Bootstrap icon name is passed to `Icon=` / `RadzenButton Icon=` / `<Icon Name=>`, Radzen renders the **literal text** of the name as visible characters instead of a glyph. Example: `Icon="trash"` displays the letters "trash" overlapping the button label — observed as **"RASH" printed over the button**. This is a visible UI bug, not a blank or missing icon. The fix is always to map the name to a valid Material Symbols name from the whitelist above.

### Unmapped legacy names — swept clean (2026-07-27)

**Status: fixed.** A full re-scan of `TestAuto.Web/Components/**/*.razor` found **sixteen** call
sites (not five) using Bootstrap/Open-Iconic names that are **not** keys in `LegacyToMaterial` and
**not** Material names — so they fell through `ResolveName`'s "return as-is" branch
(`Icon.razor.cs:60`) and hit the literal-text failure mode above. All were corrected **at the call
site**:

| Bad name | Fixed to | Call sites corrected |
|---|---|---|
| `bell` | `notifications` | `Layout/MainLayout.razor:20` |
| `person-circle` | `account_circle` | `Layout/MainLayout.razor:27` |
| `box-arrow-right` | `logout` | `Layout/MainLayout.razor:33` |
| `house` | `home` | `Layout/NavMenu.razor:12` |
| `eye` | `visibility` | `Controls/ExecutionMonitoringDialog.razor:126` |
| `x` | `close` | `Pages/ExecutionMonitoring.razor:69` |
| `media-play` | `play_arrow` | `Pages/ExecutionMonitoring.razor:39,99` |
| `database` | `storage` | `Pages/PerformanceDashboard.razor:46,143,260` |
| `arrow-clockwise` | `refresh` | `Pages/ApiExplorer.razor:15`, `Pages/DeveloperTools.razor:19` |
| `play-circle` | `play_circle` | `Pages/DeveloperTools.razor:22`, `Pages/ExecutionDetails.razor:42` |
| `info-circle` | `info` | `Pages/DeveloperTools.razor:41`, `Pages/ExecutionDetails.razor:175` |
| `arrow-left` | `arrow_back` | `Pages/ExecutionDetails.razor:24,253` |
| `bar-chart` | `bar_chart` | `Pages/ExecutionDetails.razor:60` |
| `list-check` | `checklist` | `Pages/ExecutionDetails.razor:80` |
| `exclamation-triangle` | `warning` | `Pages/ExecutionDetails.razor:249` |
| `check-circle` | `check_circle` | `Pages/Workflows.razor:377` |

**Rule (unchanged): fix at the call site — do not add these to `LegacyToMaterial`.** The map exists
for migration debt, and every entry added to it is one more name a future reader has to translate.

#### Still outstanding

- ~~`Components/Dashboard/MetricsCard.razor.cs` — `Icon` defaults to `"chart-bar"`~~ **DONE.** The
  parameter default is now `"bar_chart"` (`MetricsCard.razor.cs:8`); `chart-bar` has zero hits under
  `TestAuto.Web/`.
- Mapped-but-legacy names still in markup render correctly and are **not** urgent:
  `arrow-left-right`, `cloud-upload`, `code-slash`, `file-earmark-text`, `grid-3x3-gap`, `list-ul`,
  `pencil-square`, `question-circle`, `clock`, `gear`, `graph`, `inbox`, `speedometer2`. Replace
  opportunistically.

> **Radzen bypasses the map.** `Icon.razor.cs` only runs for `<Icon Name="…" />` (and components
> that forward into it, such as `MetricsCard`). A bare `RadzenButton Icon="…"` / `RadzenIcon Icon="…"`
> renders the string straight into the Material Icons font, so a legacy name there produces literal
> text **even if it is a key in `LegacyToMaterial`**. Always write the Material name directly on
> Radzen components.

**Rule**: Do not use legacy names in new code. Use the Material Symbols name directly.

---

## Usage Rules
1. **Use only names in this list.**  
   These are guaranteed to work with `Radzen.Icon` or your `<Icon Name="..." />` component.  
2. **If you need a new icon**, confirm it exists in [Material Symbols](https://fonts.google.com/icons).  
3. **Do not use** Bootstrap names like `diagram-3`, `pencil-square`, `box-arrow-up-right` in new code. See the Legacy Bootstrap Name Mapping section for equivalents.  
4. Prefer **consistent semantic icons**:  
   - "edit" for modify actions  
   - "account_tree" or "schema" for workflows  
   - "open_in_new" for external links
