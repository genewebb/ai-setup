---
name: ai-repo-management
description: >
  Rules for managing the AI skill repository: where skills live, how to create new skills,
  how to register them in the linker, and how to troubleshoot missing skills. Use when
  creating skills, migrating native skills, running link-to-ai.ps1, or diagnosing why
  a skill is not loading in Claude Code.
---

# AI Repository Management

Manage the AI skill repository at `{AIWorkRoot}\` — skill placement, linker registration, and link integrity for Claude Code.

## Repository Structure

```text
{AIWorkRoot}\
├── skills\                    # Source-of-truth skill folders (<name>\SKILL.md)
├── agents\                    # Agent definition files (<name>.md)
├── commands\                  # Slash-command files (<name>.md)
└── link-to-ai.ps1             # Creates directory symlinks in ~\AI\skills\
```

```text
~\AI\skills\    # = ~\.claude\skills\
  (.claude\skills is a JUNCTION to AI\skills — one directory, two paths,
   so cleaning one cleans both. Claude Code reads from here.)
  ├── <name>\  → directory symlink (mklink /D) → {AIWorkRoot}\skills\<name>\
  └── ...
```

**The link into a skill is a symbolic link, not a junction** — the target is the `Q:` share and a
junction cannot cross to a mapped drive. The junction in this layout is the single
`.claude\skills` → `AI\skills` hop, which is local-to-local.

**Never create skills directly in `~\AI\skills\`** (the Claude Code read location). All skills belong in the source-of-truth root and are linked in by the linker script.

Edits to an existing `SKILL.md` are live immediately — no linker run needed. The symlink means Claude Code reads directly from the Obsidian vault.

**If every skill vanishes at once, the drive letter is stale, not the corpus.** `Q:` comes back
`Unavailable` after a reboot while the NAS itself is fine, and with it gone all ~160 skills and every
`work-ai` slash command are silently invisible. Fix, no credentials typed:

```powershell
Get-SmbMapping | Where-Object Status -ne 'OK'      # the stale letter and the share behind it
net use <LocalPath> <RemotePath> /persistent:yes  # values from the line above
```

## Where Skills Live (Source of Truth)

| Skill Type | Source Location | Configured In |
|---|---|---|
| Work skills (speed-merchants, Profisee patterns) | `{AIWorkRoot}\skills\<name>\` | `link-to-ai.ps1` `$skills` array |
| Agents | `{AIWorkRoot}\agents\<name>.md` | `link-to-ai.ps1` `$agents` array |

## Creating a New Skill

### Step 1 — Create the skill folder and SKILL.md

```powershell
New-Item -ItemType Directory -Path "{AIWorkRoot}\skills\<name>"
```

Create `SKILL.md` with the required frontmatter:

```markdown
---
name: <kebab-case-name>
description: >
  <Noun phrase describing what it is>. Use when <triggers>.
---
```

### Step 2 — Register in the linker

Add the skill name to the `$skills` array in `link-to-ai.ps1`:

```powershell
$skills = @(
  # ... existing entries ...
  '<new-skill-name>'
)
```

Keep entries grouped logically (by domain area) in the same multi-line format as existing entries.

### Step 3 — Run the linker (once per new skill)

```powershell
pwsh "{AIWorkRoot}\link-to-ai.ps1"
```

This creates the directory symlink at `~\AI\skills\<name>`. Only needed once — after that, all edits to `SKILL.md` are live immediately. The new skill becomes available without restarting Claude Code (verified 2026-07-25).

### Step 4 — Regenerate the Overview README

`Overview\README.md` is generated from every skill's `description:` frontmatter. Adding, removing, or renaming a skill — or changing its description — makes it stale.

```powershell
pwsh "{AIWorkRoot}\Overview\Generate-SkillsReadme.ps1"
```

Verify with the gate:

```powershell
pwsh "{AIWorkRoot}\Overview\Generate-SkillsReadme.ps1" -Check
```

Exit `0` = current, exit `1` = stale. **Never hand-edit that README.**

If the new skill lands under **General** when it belongs elsewhere, add a line to the `$Overrides` map in the generator rather than editing the output. If the script throws `Categories missing from $CategoryOrder`, add the new category to `$CategoryOrder`.

## Migrating a Native Skill

A "native" skill is one that lives directly in `~\AI\skills\<name>\` without a link of any kind (i.e., it was created before the linker workflow was established, or it predates the vault move). The audit-with-update skill cannot edit native skills — migrate them first.

### Migration steps

1. Copy the skill to the source-of-truth root:

```powershell
Copy-Item -Path "~\AI\skills\<name>" `
          -Destination "{AIWorkRoot}\skills\<name>" `
          -Recurse
```

2. Add the skill name to `link-to-ai.ps1` `$skills` array (Step 2 above).

3. Delete the original native directory:

```powershell
Remove-Item -Path "~\AI\skills\<name>" -Recurse -Force
```

4. Run the linker (Step 3 above) — creates the symlink in place of the deleted directory.

## Troubleshooting

**Skill not loading in Claude Code?**

1. Check the link exists, and that its target resolves:
```powershell
Get-Item -Force "~\AI\skills\<name>" | Select-Object Name, LinkType, Target
```

`readlink` in bash reports the target string happily whether or not it resolves, so a bash-only
check reads a dead link as fine. Compare `LinkType` / `Target`, then `Test-Path` the target.

2. If missing, verify it's in `link-to-ai.ps1` `$skills` array and run the linker.

3. Check the source folder exists and has a valid `SKILL.md`:
```powershell
Test-Path "{AIWorkRoot}\skills\<name>\SKILL.md"
```

4. Restart Claude Code — skills are indexed at session start.

**Linker reports "EXISTS" but skill still not loading?**

The link exists but may point to a stale path — every link pointed at the retired `MyWorkVault` root after the vault moved. Delete the link and re-run the linker:

```powershell
Remove-Item "~\AI\skills\<name>" -Force
pwsh "{AIWorkRoot}\link-to-ai.ps1"
```

**Linker script behavior:**

- `EXISTS` — link already present; no action taken.
- `LINKED` — new link created, and the exit code **and** `Test-Path` on the target were both checked.
- `FAILED: skills/<name> (mklink exit N)` — creation failed. Before 2026-09-09 the loop printed
  `LINKED` unconditionally over every failure, so six absent skills read as linked.
- The linker uses **`mklink /D`** (directory *symbolic link*) for skill directories and `mklink` for
  agent and command files. **Not `/J`.** A junction cannot target a mapped network drive, and the
  corpus lives on the `Q:` share — `/J` fails with `Local volumes are required to complete the
  operation.` `/D` needs admin or Developer Mode, which is permitted on CORPLTR94.

**Drift report (runs automatically after every link pass):**

The link loops only ever *add*, so anything already sitting in a target tree is invisible to them. The drift report closes that gap and prints one of:

| Output | Meaning | Action |
|---|---|---|
| `Drift check: clean.` | Both trees match `$skills` exactly | None |
| `EXTRA (linked but not in $skills)` | A link **into this vault** that nobody registered — a retired skill whose array entry was removed but whose link was not | Delete the link (see the Three-Location Rule in `config-gc`) |
| `FOREIGN (links outside this vault, not managed here)` | A link whose target is **not** under `$sourceBase` — a skill owned by another root, today `~\.agents\skills` (41 skills; only `archify` is linked in) | **None.** Informational, not counted as an issue. Do not delete it and do not add it to `$skills` — a `$skills` entry with no vault folder would print `MISSING source folder` forever |
| `NATIVE (unbacked, migrate - do not delete)` | A **real folder**, not a junction. It exists only there — no vault copy, no Obsidian sync, no backup | **Migrate it** (Creating a New Skill, Steps 1–4). Deleting it destroys the only copy |
| `BROKEN link (target gone)` | Source folder was deleted but the link was left | Delete the link |
| `MISSING source folder for $skills entry` | Registered in the array but no folder exists | Remove the array entry, or restore the folder |

`NATIVE` is the dangerous one and the reason this report exists: `atomic-tests` sat unbacked in `~\AI\skills` for over a month because every existing check's scope excluded it — the linker only walks its own array, the audit only scans the vault, and the broken-junction check requires a junction.

## Quick Validation

#### List all registered skills in the linker

```powershell
Select-String -Path "{AIWorkRoot}\link-to-ai.ps1" -Pattern "'\w"
```

#### Check for broken links

```powershell
Get-ChildItem "~\AI\skills\" |
  Where-Object { $_.LinkType -and -not (Test-Path $_.Target) } |
  Select-Object Name, Target
```

#### Run the linker

```powershell
pwsh "{AIWorkRoot}\link-to-ai.ps1"
```

## Sources

- `{AIWorkRoot}\link-to-ai.ps1`
- `{AIWorkRoot}\skills\ai-repo-management\SKILL.md`
