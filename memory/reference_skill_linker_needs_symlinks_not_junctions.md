---
name: reference_skill_linker_needs_symlinks_not_junctions
description: "link-to-ai.ps1 must use mklink /D not /J — a junction cannot target the Q: share, and the script reported LINKED over every failure"
metadata: 
  node_type: memory
  type: reference
  originSessionId: ef743ea7-ebbb-46a3-a46a-a4316a6c4d42
  modified: 2026-09-09T15:12:21.559Z
---

**Measured 2026-09-09** while applying a skill audit. Three separate breakages in the skill-linking chain,
all invisible until exercised, all now fixed.

## 1. A junction cannot target a mapped network drive

The skills corpus lives on **`Q:\Work\Work\03 Shared\work-ai\skills`** (the NAS/SMB share). `link-to-ai.ps1`
used `cmd /c mklink /J` — a **junction** — which fails against a mapped drive with:

```
Local volumes are required to complete the operation.
```

**Fix: `mklink /D`** (a directory symbolic link), which does work to a network target. The 153 links that
already existed were all `LinkType=SymbolicLink`, i.e. somebody made them by hand with `/D` after the vault
moved and never updated the script. `/D` needs admin or Developer Mode; it is permitted on CORPLTR94.

## 2. The script reported LINKED over every failure

The creation loop called `cmd /c mklink ...` and then printed `LINKED:` **unconditionally**, never checking
`$LASTEXITCODE` or testing the target. So the console read:

```
Local volumes are required to complete the operation.
LINKED: skills/crewchief-library-folders
```

Six new skills were reported linked and were absent. Now guarded: it checks the exit code AND
`Test-Path` on the target, and prints `FAILED:` with the exit code otherwise.

## 3. Two stale roots pointing at a retired vault

`C:\devopslocal\ObsidianVaults\Work\MyWorkVault\` is **retired** — it now holds only `99 Documentation`.
Both `link-to-ai.ps1`'s `$sourceBase` and all eleven configured paths in the `skill-audit-with-update`
skill still pointed there. The audit consequence was the nastiest: reading the backlog through the dead
path returned *absent*, so the session read as a **first run** and a full scan would have re-proposed
candidates settled a month earlier.

## The layout, verified

| Path | What it is |
|---|---|
| `Q:\Work\Work\03 Shared\work-ai\skills\<name>\SKILL.md` | **source of truth** |
| `C:\Users\agenewe\AI\skills\<name>` | directory **symlink** to the above (what the linker writes) |
| `C:\Users\agenewe\.claude\skills` | a **junction to `AI\skills`** — one directory, two paths, so cleaning one cleans both |
| `C:\Users\agenewe\.cursor\skills` | **deleted 2026-09-09** on Gene's call — all 157 entries had been broken since the vault moved. The linker's cursor mirror is now behind `$mirrorToCursor = $false` so a re-run does not recreate it |

**How to tell a broken link from a working one:** `Get-Item -Force` and compare `LinkType` /`Target`, then
`Test-Path` the target. `readlink` in bash reports the target string happily whether or not it resolves, so
a bash-only check reads a dead link as fine.

Related: [[reference_workai_sync]], [[reference_workai_overview_readme_generated]],
[[project_ds918_nas_deployment]] (the move that broke all of this),
[[reference_no_venvs_on_nas_d_drive]].
