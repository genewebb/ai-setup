# ai-setup

Private home of my Claude Code setup: skills, agents, commands, global CLAUDE.md, hooks, settings template,
permissions, memory, stream kit. Product code is NOT here; it stays in the corporate Azure DevOps repos.

## The whole sync model

| I want to | Run |
|---|---|
| Use my setup on a machine (first time) | `git clone https://genewebb@github.com/genewebb/ai-setup.git` (`genewebb@` stops the work/personal account picker) into the machine's repos root, then `install.ps1` |
| Get changes made elsewhere | `install.ps1` (git pull --ff-only + install) |
| Send changes from this machine | `publish.ps1 -Message "..."` (secret scan, commit, rebase, push) |
| Share commands or skills with a coworker | `prof setup share profile` / `prof setup share ai-setup` (writes the `ShareRepo` clone, prints the git commands) |

```powershell
# from the clone folder
pwsh -NoProfile -File .\install.ps1            # lists every location first and asks once; -Yes skips the question
pwsh -NoProfile -File .\install.ps1 -WhatIf    # the same list, nothing written, nothing asked
pwsh -NoProfile -File .\publish.ps1 -Message "stream-author: tighten ticket clauses"   # shows the files, asks once; -Yes skips
```

`install.ps1` refuses when this clone is not the profile's `AIWorkRoot` or when the profile's `ClaudeHome` is not
the folder Claude reads for the account running it, so an install never lands where nothing reads it. It installs
the runtime, links memory, copies the PowerShell profiles, the stream-host scripts, and registers the hourly
scheduled task **AI scratch cleanup** (`bin\Clear-AIScratch.ps1`): it works only under `{ScratchRoot}`, removes
files nothing holds open and nothing wrote for 7 days plus day-old tool leftovers, then empty folders, and logs one
line per run to `{ScratchRoot}\ai-config-work\Clear-AIScratch.log`. No Claude session is involved.

`publish.ps1` publishes `main` only, refuses while a rebase or merge is unfinished, and tells a conflict (files to
resolve, then `git rebase --continue`, re-run) apart from an unreachable remote (your commit is kept; re-run later).

## Machine values

Machine-specific paths live only in each machine's profile `ProfileMachineConfig.md`, never here. Shared files
refer to them as `{Key}`. The profile's `AIWorkRoot` points at this clone, and its git policy table must allow
commit and push for `{ReposRoot}\ai-setup`.

## Sharing at work

This repo is the source. `prof setup share` hands picked parts of it to a coworker through one shared git repo (the
`ShareRepo` machine key; today ADO `Products/_git/speed-merchants-dba`, under its `ai\` folder):

- `prof setup share profile`: categories and commands of the PowerShell profile, really trimmed, with an installer and a
  machine-settings template (`ai\profile`)
- `prof setup share ai-setup`: Claude skills as one plugin per category (`ai\plugins\<category>`) behind a plugin
  marketplace at the repo root; `[[skill]]`, `` `skill` `` and `/skill` references become `<category>:<skill>` in the copy

The repo is the state: what it holds is preselected, unpicking removes it. A skill is refused when it uses a
machine-profile `{Key}` path or references a skill that is not shared with it; anything that looks like a secret stops
the share; every line matching a `share.yaml` `blockedPatterns` entry (personal accounts, hosts, personal paths) is
listed and needs a yes. share never commits: it prints the `git add / commit / push` lines. Design and coworker steps:
vault `99_Frequent\Profile\Share Design.md` and `Coworker Handoff.md`; `prof setup share help` has the short version.

## Secrets

Never committed. `.gitignore` excludes the known shapes and `publish.ps1` runs `tools\Find-Secrets.ps1` on every
change; a hit blocks the commit. Machine secrets stay in `{SecretsDir}`.
