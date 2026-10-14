---
name: config-gc
description: >
  Garbage collection for the local Claude Code configuration — scans skills,
  memory, hooks, permissions, MCP servers, project history, and caches for
  redundant, stale, orphaned, or conflicting entries, then walks through a
  confirm-each-deletion cleanup with soft-delete and an undo log. Use when
  asked to clean up or audit the config, when there are too many skills, when
  session startup feels slow, after installing a batch of new skills, or for a
  periodic (~monthly) config review.
---

# Config GC

Borrowed from runtime garbage collection: periodically scan for objects that are
no longer referenced, redundant, expired, or low-value, and reclaim the space.

**The critical difference: collection requires a human in the loop. Never delete
autonomously.**

## When to Activate

- "Clean up my config", "config GC", "too many skills", "my setup is bloated"
- A periodic (~30 day) review is due
- Immediately after adding a batch of skills — that is exactly when overlap with
  the existing corpus appears

Do **not** activate for: cleaning project source (that is refactoring), clearing
chat history, or uninstalling Claude Code.

## Design Philosophy

1. **Append-only configs leak.** Skills, memory files, hooks, and permission
   entries only ever get added. Without review they rot silently.
2. **Regular audits beat one-time purges.** Scan every ~30 days; propose a small
   batch each time. Cap a run at ~20 candidates.
3. **Per-channel strategies.** Each accumulation type has its own staleness
   signals. Do not apply one rule everywhere.
4. **Soft-delete first.** `.disabled` rename > move to `_gc_trash\<date>\` >
   real deletion. Always keep an undo path.
5. **Forced human-in-the-loop.** Every candidate gets its own `[y/n/skip]`.
   There is no "yes to all".
6. **Keep a log.** Every run appends to `~\.claude\gc_log.md`: what was touched,
   why, and how to undo it.

## The Three-Location Rule (read before deleting any skill)

A work-ai skill exists in **three** places:

```text
work-ai\skills\<name>\                     <- source of truth (Obsidian-synced)
  |-- junction --> %USERPROFILE%\AI\skills\<name>          (= ~\.claude\skills)
  '-- junction --> %USERPROFILE%\.cursor\skills\<name>
```

- Deleting a junction does **not** delete the source.
- Deleting the source **orphans two junctions**, which then resolve to nothing.

**Correct removal order, every time:**

1. Remove the name from the `$skills` array in `work-ai\link-to-ai.ps1`
2. Delete both junctions
3. Move the source folder to `_gc_trash`

Never start at step 3.

## Scan Channels

| # | Channel | Target | Staleness / redundancy signals |
|---|---------|--------|-------------------------------|
| 1 | Skills | `work-ai\skills\*` vs `$skills` in `link-to-ai.ps1` | In the array but no folder; folder but not in the array; heavily overlapping names; domain no longer worked in; empty or broken `SKILL.md` |
| 2 | Junctions | `~\AI\skills`, `~\.cursor\skills` | Junction whose target no longer exists; junction with no matching array entry |
| 3 | Memory | `~\.claude\projects\<project>\memory\*.md` + `MEMORY.md` | Orphan file (present, not in the index); orphan index line (in index, no file); two entries for one topic; contents contradicted by a newer entry; dates that have passed |
| 4 | Hooks | `~\.claude\scripts\*.ps1` vs `settings.json` | Script on disk referenced by no hook config; superseded versions |
| 5 | Permissions | `settings.json` + `settings.local.json` | **allow/ask collisions**; exact duplicates; entries shadowed by a broader pattern; one-off grants from past experiments; missing `/c/...` twin for a `C:\...` entry |
| 6 | MCP servers | configured server list | Fails to connect; functionally duplicate tool sets; long unused |
| 7 | Project history | `~\.claude\projects\*\` | Stale handoff snapshots superseded by newer state |
| 8 | Caches | `~\.claude\` cache / file-history / shell-snapshots / logs | Large and >30 days old |

## Workflow

1. **Scan** the requested channels (or all). Collect: path, channel, the signal
   that flagged it, size, last-modified.
2. **Rank** by confidence — broken or orphaned is high; merely old is low.
   Present as a numbered table. Cap at ~20 per run.
3. **Confirm one at a time.** Show the evidence, then ask `[y/n/skip]`. The user
   may stop at any point.
4. **Soft-delete** confirmed items. Only hard-delete when explicitly asked.
5. **Log** the run to `~\.claude\gc_log.md`.
6. **Report**: reclaimed size, channels that came back healthy, next review date.

## Scan Commands

### Channel 1 + 2 — skill / junction drift

```powershell
$w   = '{AIWorkRoot}'
$src = (Get-ChildItem "$w\skills" -Directory).Name
$raw = Get-Content "$w\link-to-ai.ps1" -Raw

# Scan ONLY the $skills = @( ... ) block. A naive whole-file regex also matches
# the 'skills' / 'agents' literals inside the Join-Path calls and reports them
# as phantom missing skills.
$block = if ($raw -match '(?s)\$skills\s*=\s*@\((.*?)\n\)') { $Matches[1] } else { '' }
$reg = [regex]::Matches($block, "'([^']+)'") |
         ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique

Write-Output '--- in linker, no source folder (breaks on next run) ---'
$reg | Where-Object { $_ -notin $src }

Write-Output '--- source folder, not in linker (never loads) ---'
$src | Where-Object { $_ -notin $reg }

Write-Output '--- junctions whose target is gone ---'
Get-ChildItem "$env:USERPROFILE\AI\skills" |
  Where-Object { $_.LinkType -and -not (Test-Path $_.Target) } |
  Select-Object Name, Target

Write-Output '--- NATIVE dirs: real folders, not junctions (unbacked, will not survive a rebuild) ---'
Get-ChildItem "$env:USERPROFILE\AI\skills" -Directory -Force |
  Where-Object { -not (Get-Item $_.FullName -Force).LinkType } |
  Select-Object Name, LastWriteTime
```

A native dir is **not** a GC candidate — it is a **migration** candidate. It exists only in the read location: not Obsidian-synced, not in the linker, no copy anywhere. Deleting one destroys the only copy. Move it into the ai-setup clone per `ai-repo-management`, never trash it.

### Usage signal — which skills are actually invoked

The strongest staleness evidence, and the easiest to get wrong.

**Do not grep transcripts for a skill's name.** Every session injects the full available-skills catalog into a system reminder, so essentially every session "mentions" every skill. That measures the catalog, not usage. Count invocations instead:

```powershell
$files = Get-ChildItem "$env:USERPROFILE\.claude\projects" -Recurse -Filter '*.jsonl'
$inv = $files | Select-String -Pattern 'Launching skill: ([a-z0-9:_-]+)' -AllMatches |
    ForEach-Object { $_.Matches } | ForEach-Object { $_.Groups[1].Value }

"total invocations: $($inv.Count) across $($files.Count) sessions"
$inv | Group-Object | Sort-Object Count -Descending | Select-Object Name, Count
```

Anything absent from that list has never been invoked in the retained history.

Read the result honestly before acting on it:

- **Transcript retention is finite.** Check the oldest session date and state the window. A skill created before it cannot be ruled out on this evidence alone.
- **Zero invocations is not automatically "retire."** Corroborate with a second signal — no target repo/stack, no inbound references, excluded from audits, domain no longer worked in.
- **A low count is not "unused."** A skill invoked twice may have been decisive both times.
- Skills invoked from other harnesses (Cursor, Copilot) do not appear here.

### Channel 3 — memory orphans in both directions

```powershell
$m     = "$env:USERPROFILE\.claude\projects\C--devops-repos-speed-merchants\memory"
$idx   = Get-Content (Join-Path $m 'MEMORY.md') -Raw
$files = (Get-ChildItem $m -Filter '*.md' | Where-Object Name -ne 'MEMORY.md').Name

Write-Output '--- file exists but is not linked from MEMORY.md ---'
$files | Where-Object { $idx -notmatch [regex]::Escape($_) }

Write-Output '--- MEMORY.md links a file that does not exist ---'
[regex]::Matches($idx, '\(([^)]+\.md)\)') | ForEach-Object { $_.Groups[1].Value } |
  Where-Object { $_ -notin $files }
```

### Channel 4 — orphaned hook scripts

```powershell
$cfg = Get-Content "$env:USERPROFILE\.claude\settings.json" -Raw
Get-ChildItem "$env:USERPROFILE\.claude\scripts" -Filter '*.ps1' |
  Where-Object { $cfg -notmatch [regex]::Escape($_.Name) } |
  Select-Object Name, LastWriteTime
```

Note the dispatcher pattern: a script invoked as `hook-dispatch.ps1 -Id <name>`
is referenced in `settings.json` only by its `-Id`, not its filename. Check for
`-Id <name>` before declaring `<name>.ps1` an orphan.

### Channel 5 — permission drift (highest value per minute)

Do not hand-roll this scan. Run the checker:

```powershell
pwsh "$env:USERPROFILE\ai\permissions\Check-PermissionsDrift.ps1" -Detail
```

Exit `0` = every client matches canonical `permissions.yaml`; exit `1` = drift.
It never writes. It compares Claude Code **and** VS Code / Copilot against the
canonical tiers, and understands that each client expresses them differently —
VS Code has no middle tier, so an `ask` command must match **no** approve
pattern.

It also catches prefix collisions, which a manual read reliably misses:
`"/^fd/": true` silently auto-approved the deny-tier `fdisk`, and
`"/^docker build/"` matches `docker builder prune`.

Also check that every `C:\...` path entry has its `/c/...` twin, since Bash and
PowerShell tool calls present paths differently.

**Never hand-edit `settings.json` permissions.** The canonical source is
`~\ai\permissions\permissions.yaml`. Fix there, re-sync, then re-run the checker
until it exits 0. See `permissions-yaml`.

### Channel 8 — large stale caches

```powershell
Get-ChildItem "$env:USERPROFILE\.claude" -Recurse -File -ErrorAction SilentlyContinue |
  Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) } |
  Sort-Object Length -Descending |
  Select-Object -First 20 FullName,
    @{ n = 'MB'; e = { [math]::Round($_.Length / 1MB, 2) } }, LastWriteTime
```

## Soft-Delete with an Undo Path

```powershell
$gcDate = Get-Date -Format 'yyyy-MM-dd'
$trash  = Join-Path $env:USERPROFILE ".claude\_gc_trash\$gcDate"
New-Item -ItemType Directory -Path $trash -Force | Out-Null

# Retiring a skill - only AFTER removing it from $skills and deleting both junctions.
Move-Item '{AIWorkRoot}\skills\dead-skill' $trash
Add-Content (Join-Path $env:USERPROFILE '.claude\gc_log.md') `
  "$(Get-Date -Format o)  moved skills\dead-skill -> _gc_trash\$gcDate\  (undo: Move-Item back, re-add to skills array, re-run linker)"
```

JSON has no comments, so for a permission removal: back up the file, record the
removed entry verbatim in `gc_log.md`, then remove it.

## Anti-Patterns

- **Bulk approval.** "Delete all 15? [y/n]" defeats the design. One item, one
  decision.
- **Hard-deleting on the first pass.** No `_gc_trash` copy means you did it wrong.
- **Treating "old" as "dead".** A skill untouched for 60 days may be seasonal —
  a release-cycle or upgrade skill is idle most of the year. Age is a signal,
  not a verdict.
- **Deleting the source folder first.** See the Three-Location Rule.
- **Cleaning memory by truncation.** Merging two contradicting memory files
  means reading both and keeping the newer truth, not deleting the longer one.
- **Hand-editing `settings.json` permissions.** Route through `permissions-yaml`.
- **Wandering outside `~\.claude` and `work-ai`.** Config GC never enters a
  source tree.

## Best Practices

- Run after big additions, not only on a calendar.
- When two skills overlap, prefer retiring the one with the weaker trigger
  description — it is the one that was probably never firing.
- Permissions is the highest-value channel per minute spent.
- Keep `gc_log.md` forever. It is tiny, and "when did I disable that and why"
  comes up more than you would expect.

## Related Skills

- `skill-audit-with-update` — audits skill *quality*; this audits skill
  *existence*. Run the audit on what survives GC.
- `context-budget` — quantifies what GC then reclaims. Run it first to rank.
- `permissions-yaml` — the only correct path for permission changes.
- `ai-repo-management` — where skills live (ai-setup clone) and how changes reach machines.

---

Adapted from ECC (MIT, © 2026 Affaan Mustafa) — <https://github.com/affaan-m/ECC>
