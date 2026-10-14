---
name: AI portable toolkit setup
description: Gene's ~/AI repo setup with work-ai centralized skills/agents, configured for Windows/PowerShell/Wave.ai
type: project
originSessionId: 4d81e53a-eb92-41c9-b08e-1fce43313a83
---
Gene set up the bobthearsonist/ai portable AI toolkit at ~/AI on 2026-05-11, then centralized all Profisee-specific AI content into work-ai on the same day.

**Architecture:**
```
C:\devopslocal\repos\work-ai\          ← Single source of truth (git repo)
├── skills/ (16 directories with SKILL.md)
├── agents/ (7 .md files)
└── rules/ (7 .md files)
        │ local.yaml collection
        ▼
C:\Users\agenewe\AI\                   ← Portability layer
├── skills/ (16 junctions + 10 built-in = 26)
├── agents/ (7 symlinks + 1 built-in = 8)
└── rules/global/ (7 copied + 7 built-in = 14)
        │ junctions
        ▼
C:\Users\agenewe\.claude\              ← Claude Code reads from here
├── skills/ → ~/AI/skills/
└── agents/ → ~/AI/agents/
```

**What was done:**
- Cloned bobthearsonist/ai repo at C:\Users\agenewe\AI
- Created PowerShell equivalents: setup.ps1, scripts/sync.ps1, scripts/doctor.ps1
- Created work-ai repo at C:\devopslocal\repos\work-ai with 16 skills (converted from Cursor .mdc rules/commands), 7 agents (converted from OpenCode format), 7 rules
- Registered work-ai as a `local.yaml` collection; created junctions via link-to-ai.ps1
- Windows symlinks: ~/.claude/CLAUDE.md → ~/AI/AGENTS.md, ~/.claude/skills → ~/AI/skills (junction), ~/.claude/agents → ~/AI/agents (junction)
- doctor.ps1 passes all checks (requires pwsh, not powershell.exe)
- Inventory doc at C:\devopslocal\Documentation\claudecode\ai-inventory.md

**Key details:**
- sync.ps1 has a yq compatibility issue with external skills; local collections work but junctions were created manually via link-to-ai.ps1
- doctor.ps1 requires PowerShell 7 (`pwsh`) due to `??` operator
- Skills converted from: .cursor/rules/*.mdc (dotnet, blazor, mcp patterns) and .cursor/commands/ (pr-review, task-generator, bug-generator)
- Agents converted from: .opencode/agents/ (scenario-designer, custom-metric-coder, custom-parm-editor, config-generator, config-validator, job-implementer, testauto-reviewer)

**Why:** Centralize AI skills/agents portably across Claude Code, Copilot, and other clients. Avoid scattered copies across .cursor/, .opencode/, .github/ directories.

**How to apply:** When Gene mentions skills, agents, or the AI repo, this is the system. Edit content in work-ai repo, then re-run link-to-ai.ps1 if new items are added. Run `pwsh -NoProfile -File ~/AI/scripts/doctor.ps1` to verify.
