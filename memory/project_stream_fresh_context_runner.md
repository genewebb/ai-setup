---
name: project-stream-fresh-context-runner
description: Stream roles can run as Start-StreamRunner.ps1 (one fresh headless claude -p session per ticket or timed tick) instead of /loop; probes verified 2026-10-04
metadata:
  node_type: memory
  type: project
  originSessionId: 185f5665-8770-43d9-9ee7-eb0430a4dfbe
  modified: 2026-10-04T17:55:05.013Z
---

On 2026-10-04 the owner ruled that every author and builder ticket, and every timed review (coordinator, integrator, plan, status, kit), should start with a clean context. The kit now has `stream-kit\scripts\Start-StreamRunner.ps1 -Repo -Role <role>`. Each role SKILL.md points to it.

**Why:** In one long `/loop` session, context builds up from ticket to ticket and auto-compaction carries stale state forward. The model cannot run /clear on itself.

**How to apply:**
- Probes measured on 2026-10-04:
  - `claude -p "/stream-build status ..." --permission-mode bypassPermissions --permission-prompts none --output-format json` invokes the skill (3 turns, $0.22).
  - A child started with `Start-Process pwsh -WindowStyle Hidden` from inside a `-p` session keeps running after the session exits.
  - A `run_in_background` task does not survive the session's exit.
- Session ids: author and build get a new id per launch. Timed roles keep one id per runner, which the integrator lock needs.
- When the integrator moves from `/loop` to the runner, the old session still holds `integrator.lock`. The runner's cycles get exit 5 until that lock goes stale (20 min) or is handed over.
- Stop files: `.streams\runners\STOP-<role>` or `.streams\runners\STOP`. State is in `.streams\runners\*.json`; per-session results are in `.streams\logs\runner\`.
- EnhanceStream build (2026-10-04, design `S:\AIWork\Design\EnhanceStream.md`, guide `S:\AIWork\Design\StreamGuide.md`): `-Live` (interactive + `--remote-control`, ends through the `stream-unit` mod's `unit_done` tool), `-Stream` (stream-json feed), lessons via `Add-Lesson.ps1` in `.streams\lessons\<role>.md`.
- `ai.ps1` runs `Install-AIMachine.ps1 -Launch` on every start: measured 111 s. The runner now checks once per 60 min (`ai.ps1 --version`) and starts claude directly with ai's env.
- Claude Code 2.1.286 mod layout: `.claude-plugin/plugin.json` + `hooks/hooks.json` `{ "modules": ["./register.ts"] }`; get the real types with `claude -p "/plugin-types"`. `$.command.run` is refused inside `tool.call` (deadlock guard), so run `/exit` from `turn.complete`; a `turn.complete` with `agentId` is a subagent's. Test with `claude plugin test <dir>`.
- Live probe: a script-started interactive session with `--plugin-dir` loaded the mod with no prompt and exited itself; 9 s session, $0.35.
- Owner launches runners with pwsh profile commands (2026-10-04, replaced Start-MyStreaming): `addStreams -Repo <repo>` (new 'Streams' WezTerm window: Planner, Integrator, Kit, Coordinator, Status, in that owner-set order) and `addStreamTab -Author|-Builder -Repo <repo> [-Count N]` (tabs 'Author N'/'Builder N', lowest free numbers). Each tab: CLAUDE_DISABLED_HOOKS=gateguard, Set-Location repo, runner -Live. Refuse on STOP files (-ClearStop) and on open role tabs (-Force).
- Runner scripts run under StrictMode: any `$obj.missing` on JSON throws. Read result/event fields through a PSObject.Properties check; wrap 0/1-item `if` results in `@()`.

Related: [[project-stream-kit-replaces-myloop]], [[feedback-coordinator-defer-to-live-planner]]
