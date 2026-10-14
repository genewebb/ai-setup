---
name: project_aiwork_move_to_s_drive
description: "The AI setup (work-ai skills/agents/commands + global CLAUDE.md, hook scripts, memory) is moving from the Obsidian vault on Q: to a plain share S:\\AIWork behind a firewall (RDP only from CORPLTR94); staging tree built 2026-09-15 at C:\\tmp\\AIWork; guide at C:\\Bits\\AIWork-Migration-and-Sync.md"
metadata: 
  node_type: memory
  type: project
  originSessionId: 71018226-2ec4-450a-8dc9-2c5c6c328048
  modified: 2026-09-15T12:42:45.183Z
---

Gene decided 2026-09-15 to move the AI setup off the Obsidian vault (`Q:\Work\Work\03 Shared\work-ai`) onto `S:\AIWork` ("the real destination, no two copies and setups") and share it with one machine on that network plus three on another network. **CORPLTR94 cannot map S: (firewall); the tree goes over an RDP session.** A first idea of `Z:\PerformanceTesting\AIWork` was withdrawn the same morning.

**Guide:** `C:\Bits\AIWork-Migration-and-Sync.md` (Phases A-D, verification, traps, four appendix scripts).

**State 2026-09-15 08:45:** Phase A steps A.1-A.6 DONE into staging `C:\tmp\AIWork` (1151 files, 16.6 MB): work-ai tree minus its stray `.git`, `claude\` folder (CLAUDE.md, tokenized `settings.template.json`, statusline, 18 hook script files, 376 auto-memory files, `graph\memory.jsonl`, permissions.yaml, profile region, mcp-servers.md), `Install-AIWork.ps1`, `Sync-AIWork.ps1`, `.gitignore`, README, linker with `-SourceBase`/`-ClaudeDir` params + `archify` + `myloop.md`. Every `Q:\...\work-ai` path rewritten to `S:\AIWork` (12 files). Secret scan clean. Pending: A.7 git init + hosted remote (which side can reach it is unknown), A.8 RDP copy + count check (expect 174 skills / 12 agents / 3 commands), then delete `C:\tmp\AIWork`. **Phase B for CORPLTR94 is OPEN**: B-1 local clone + hosted remote, B-2 RDP copies by hand, or B-3 stay on Q:.

**SMVMTR2 WIRED 2026-09-15 09:54** (prod TestAuto runner, user `speedmerchants`, S: = Azure Files share `\smshareddrive.file.core.windows.net\sharedfiles`): claude.exe in `C:\Deploy\Claude` via `C:\Bits\Install-ClaudeTo.ps1` (DISABLE_AUTOUPDATER=1, doctor warns about ~\.localin, ignore), `C:\Bits\Verify-AIWork.ps1 -Install` green, 173 links, plugins, MCP = memory/filesystem/speedMcpRemote + `smvmtr2_testauto`, `smvmdb2_modelsource`, `smvmdb2_profisee` (Windows auth, uv via winget), settings roots `C:\devops\myworkspace`, `C:\Deploy`, `S:\AIWork`. Smoke: 237 skills, 16 agents, 128 MCP tools. Runner DB is `testauto` NOT `speedmerchants`. Guide section C.10 = the exact sequence for SMVMTR1/SMVMTR3 (only `$n` changes). Staged `claude\mcp-servers.md` has the runner block; S: copy still owes that file.

**Design:** per machine `Install-AIWork.ps1` (run from the root; `$PSScriptRoot` = root): symlinks for skills/agents/commands/CLAUDE.md, COPIES for hook scripts + statusline, settings.json GENERATED from the template with `{{HOME}}`/`{{HOME_FWD}}`/`{{HOME_MSYS}}`/`{{AIWORK}}` tokens. `~\AI` (bobthearsonist/ai clone) retired after the move. Memory shared in the root (D2 default).

**Unbacked pieces found:** `~\.claude\commands\myloop.md` (native), all of `~\.claude\scripts\*.ps1` (native), `archify` in the foreign root `~\.agents\skills`. `~\.claude.json` holds an ADO PAT in plain text in the `azure-devops` args; never copy that file.

**How to apply:** until Phase B is decided, CORPLTR94 still resolves through Q: ([[reference_nas_drive_letters_stale_after_reboot]], [[reference_skill_linker_needs_symlinks_not_junctions]]). `ai-repo-management` SKILL.md still describes the OLD layout and must be rewritten for S: once the move is real. Related: [[reference_workai_sync]], [[claude-account-profile-commands]].
