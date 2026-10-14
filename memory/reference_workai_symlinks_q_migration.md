---
name: workai-symlinks-q-migration
description: 2026-08-21 fixed 159 broken work-ai links (skills/agents/commands) left dangling by the 8/20 DS918 vault move — junctions can't target SMB, all converted to symlinks aimed at Q:
metadata:
  type: reference
---

The 8/20 DS918 migration moved the vault from `C:\devopslocal\ObsidianVaults\Work\MyWorkVault` to mapped SMB `Q:\Work\Work`, silently breaking every reparse point into the old path: `~/.claude/commands/myworkflow.md` (symlink), all ~151 `C:\Users\agenewe\AI\skills\*` (JUNCTIONS) and 7 `AI\agents\*.md` (symlinks). Symptom: /myworkflow and all personal skills vanished from Claude Code skill listings.

Fixed 2026-08-21: all repointed to `Q:\Work\Work\03 Shared\work-ai\{skills,agents,commands}\...` as **symbolic links** (NTFS junctions cannot target network volumes — the skills junctions had to change type, not just target). Developer mode allows non-admin symlink creation on this box.

**Why:** any future path move of the vault re-breaks 159 links at once; PowerShell `Get-ChildItem | Where LinkType -eq 'SymbolicLink'` misses junctions — filter on `Attributes -band ReparsePoint` instead; PS 7 `Test-Path` returned True for broken symlinks here, don't trust it for link health — compare `.Target` prefix.

**How to apply:** if skills/commands go missing again, run `find /c/Users/agenewe/AI ~/.claude -xtype l` in git-bash first. Repoint loop: enumerate ReparsePoints whose Target starts with the dead root, delete link (`[IO.Directory]::Delete($path,$false)` for dir links), `New-Item -ItemType SymbolicLink` at the new root. Caveat: everything now depends on Q: being mounted — WireGuard/offline sessions lose all personal skills again (symptom identical). Related: [[project_ds918_nas_deployment]], [[reference_workai_sync]].
