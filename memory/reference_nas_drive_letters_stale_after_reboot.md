---
name: reference-nas-drive-letters-stale-after-reboot
description: After a reboot the SynologyDS918 mapped drives come back Unavailable, which silently hides the ENTIRE skill library and every work-ai slash command because they are symlinks into Q:
metadata:
  type: reference
---

**Measured 2026-09-09 on CORPLTR94** after a reboot at 11:16. `net use` showed all five NAS
mappings **Unavailable**, while the NAS itself was fine — `Test-NetConnection SynologyDS918 -Port 445`
True and `Test-Path \\SynologyDS918\obsidian` True. Only the drive-letter mappings were stale.

| Letter | Share |
| --- | --- |
| `Q:` | `\\SynologyDS918\obsidian` — **the one that matters** |
| `D:` | `\\SynologyDS918\devopslocal` |
| `F:` | `\\SynologyDS918\Family` |
| `O:` | `\\SynologyDS918\OneDriveArchive` |
| `V:` | `\\corpnas01\Users` |

**Why it is worse than a missing drive.** `~\.claude\skills\*` and `~\.claude\commands\*` are
**symlinks into `Q:\Work\Work\03 Shared\work-ai\`** (see
[[reference_skill_linker_needs_symlinks_not_junctions]]). With `Q:` down, `/myworkflow` resolves to
nothing and **all ~150 skills are invisible** — the session's available-skills list silently shrinks to
the two that live on `C:`. Nothing errors; the capability is just gone. `.loop\tools\Write-Schedule.ps1`
also defaults `-OutPath` to `Q:\Work\Work\99 Documentation\speed-merchants\vNext\TaskList.md`.

**Fix, no prompt, no credentials typed** (the saved credential is still good, which the UNC test
proves):

```powershell
net use Q: /delete /y
net use Q: \\SynologyDS918\obsidian /persistent:yes
```

**Two traps measured 2026-09-12 (second reboot):** (1) without the `/delete /y` first, `net use` asks
"overwrite the remembered connection? (Y/N)"; a non-interactive shell answers nothing and the mapping stays
Unavailable. (2) Run it from the **PowerShell** tool, not Git Bash: MSYS path conversion mangles `/delete`
and `/y` into paths and the command silently does nothing. VERIFIED 2026-09-12: a running session DOES re-scan
after the remap; the next Skill invocation (typed `/myfable`) loaded it and the full list reappeared. No
restart needed.

**Diagnose in one line** — a dead symlink target is the tell: `ls -la ~/.claude/commands/` shows the
link, `cat` on it fails with "No such file or directory".

Related: [[reference_workai_sync]] · [[project_doc_location]]
