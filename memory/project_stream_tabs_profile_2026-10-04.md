---
name: project_stream_tabs_profile_2026-10-04
description: "Stream tabs 10/4: Planner/Integrator/Kit/Coordinator/Status = ONE long /loop session each + stream-compact mod at 35%; Author/Builder = fresh-context runners; profile cmds addStreams/addStreamTab/stopStreams/removeStreamTab"
metadata:
  node_type: memory
  type: project
  originSessionId: 7fb21f1f-143d-43f4-acf3-a5550ca6256e
  modified: 2026-10-04T19:50:32.046Z
---

Owner rulings 2026-10-04:
- Planner, Integrator, Kit, Coordinator, Status run as ONE long interactive session per WezTerm tab (`claude --permission-mode bypassPermissions --plugin-dir <stream-kit\mods\stream-compact> -n <Tab> '/loop ...'`). Fresh-session-per-tick made those windows unusable. The stream-compact mod compacts after a turn at `STREAM_COMPACT_PCT` = 35.
- Authors and builders stay on `Start-StreamRunner.ps1 -Live -Tab '<Author N>'`: a fresh session per ticket or build.
- Capacity is NOT fixed: Gene decides by cost and resources. Optional `StreamMaxAuthors` / `StreamMaxBuilders` rows in ProfileMachineConfig.md (blank = no limit). Supersedes [[project_stream_capacity_two_authors_two_builders]].
- Profile: `addStreams -Repo` (Planner first, waits for its claude.exe), `addStreamTab -Author|-Builder -Count -Repo`, `stopStreams` (STOP files for runners; long sessions listed, `-CloseSessions` closes), `removeStreamTab -Number`. All have `-DryRun` and `-Help`. Long-session tabs keep `.streams\tabs\<tab>.json`.
- `$.session.compact` is refused in headless `-p` ("not available in a headless (-p / SDK) session yet"), so the mod is proven only by its unit tests until a live interactive session runs it.
- The laptop cannot reach the Azure share TR1's skills symlink to. Deploy path: Sync-Machine laptop -> TR1 `D:\AIWork\work-ai`, then `ai` on TR1 applies it to the share.

Related: [[project_profile_machine_config]], [[project_machine_sync_skill_2026-10-01]], [[reference_wezterm_cli_autostarts_mux]].

2026-10-04 16:21: Gene confirmed addStreams/addStreamTab running fine on SMVMTR1 (deployed by the 15:48 hourly runner launch check; no share-only edits lost). Compact toast at 35% not yet reported.
