---
name: skill-profile
description: >
  Bulk on/off control of which skills load into the session listing — by category or picked per task — to keep it inside its context budget.
  Use when skill descriptions are being truncated, when switching between TestAuto and CrewChief work, when asked which skills a task needs,
  or to audit skill usage, category and cost.
---

# Skill Profiles

Every enabled skill's name and description is rendered into the system prompt of
every session. That listing is budgeted at roughly **1% of the context window**
(~10,000 tokens on a 1M model). Past the budget descriptions are truncated, and
skill routing degrades silently — the skill is still installed, but the model can
no longer tell what it is for.

All skills enabled costs **~18,100 est. tokens**: 80% over budget.

`Set-SkillProfile.ps1` does everything mechanical. This skill supplies the one
judgement it cannot: which skills a given task actually needs.

## Script location

```text
{AIWorkRoot}\Set-SkillProfile.ps1
```

## Two speeds — say which one you mean

| Effect | Lands |
|---|---|
| Disabled skills are refused on invocation | **Immediately** — `settings.json` is re-read per call |
| Listing shrinks, tokens freed, truncation stops | **Next session** — run `/clear` |

Never tell the user a profile change "saved tokens" in the current session. It
did not. It changed what can be *invoked*; the listing is assembled at session
start.

## Modes

### Status — what is on and what it costs

```powershell
pwsh "{AIWorkRoot}\Set-SkillProfile.ps1" -Status
```

### Set — enable whole categories

```powershell
pwsh "{AIWorkRoot}\Set-SkillProfile.ps1" -Set crewchief,harness,general
```

Aliases: `testauto`, `crewchief`, `testdata`, `profisee`, `dotnet`, `blazor`,
`harness`, `ai-authoring`, `general`. Everything not listed is disabled.

Category sizes, so you can predict the result:

| Category | Skills | Est. tok |
|---|---|---|
| TestAuto | 68 | 9,149 |
| CrewChief | 20 | 3,689 |
| Harness | 17 | 1,569 |
| AI Authoring | 11 | 1,218 |
| .NET | 10 | 974 |
| General | 7 | 488 |
| Profisee | 4 | 557 |
| Blazor | 2 | 295 |
| TestData | 1 | 188 |

`-Set crewchief,harness,general` lands at 5,830 — comfortably under. Every profile
also carries `skill-profile` itself (84 tok), so a total is always slightly above
the sum of the categories picked.
**`-Set testauto` alone is 9,149 and leaves almost nothing spare**, which is why
TestAuto work needs `for`, not a category switch.

### For — pick a set for one task

This is the mode that earns its keep. Three steps:

1. Read the catalogue. It is on disk, not in context, so it lists **every** skill
   including currently disabled ones:

```powershell
pwsh "{AIWorkRoot}\Set-SkillProfile.ps1" -Catalog
```

2. Choose from it. Each row carries `name`, `category`, `tokens`, `uses`,
   `lastUsed`, `enabled`, `slashOnly`, `description`. Select what the stated task
   needs and keep the running `tokens` total under 10,000. Prefer skills whose
   description names the exact subsystem in the task over ones that merely share
   a prefix.

3. Commit the selection:

```powershell
pwsh "{AIWorkRoot}\Set-SkillProfile.ps1" -Apply seq-query,testauto-matching-scenarios,diagnose
```

Always include the cross-cutting skills the task will need regardless of domain —
typically `documentation-location`, `diagnose`, and the relevant `dotnet-*` or
`blazor-*` patterns. A profile that only contains domain skills strands the
session when it needs to write a doc or debug a failure.

### Reset — everything back on

```powershell
pwsh "{AIWorkRoot}\Set-SkillProfile.ps1" -Reset
```

### Worksheet — reviewable table with Category and Status

```powershell
pwsh "{AIWorkRoot}\Set-SkillProfile.ps1" -Worksheet
```

Writes `{ScratchRoot}\claude-skill-disable-list.md`, never-used skills first, with
Category and Status columns. Regenerate rather than hand-editing it.

## What is protected

- **`skill-profile` itself** is never disabled. It is the only way back.
- **Slash-only skills** (`disable-model-invocation: true` — `teach`, `zoom-out`)
  are never written. They cost 0 listing tokens, and disabling one would break
  its slash command for no gain.

## Gotchas

- **`pwsh -File` does not bind arrays.** `-Set a,b,c` arrives as the single
  string `"a,b,c"`. The script splits on commas itself, so both styles work —
  do not "fix" a caller that passes a bare comma list.
- **Categories come from `skill-taxonomy.ps1`**, shared with
  `Overview\Generate-SkillsReadme.ps1`. A new skill that does not carry a known
  prefix (`testauto-`, `crewchief-`, `dotnet-`, …) lands in **General** until it
  gets a line in `$Overrides`. Add it there, not in a second map.
- **Every write takes a backup** at `settings.json.bak-skillprofile-<stamp>` and
  is validated before it replaces anything. Only the `skillOverrides` key is
  touched; all sibling keys stay byte-identical.
- **The catalogue is ~61,000 chars** (~15k tokens) with truncated descriptions.
  That cost is paid once inside this skill's invocation, not per session — but do
  not read it when `-Status` would answer the question.

## Related

- `ai-repo-management` — where skills live (ai-setup clone), install and publish
- `config-gc` — drift and cleanup across the three skill locations
- `context-budget` — measuring everything else loaded into a session
