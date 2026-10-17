# ai-setup

Private home of my Claude Code setup: skills, agents, commands, global CLAUDE.md, hooks, settings template,
permissions, memory, stream kit. Product code is NOT here; it stays in the corporate Azure DevOps repos.

## The whole sync model

| I want to | Run |
|---|---|
| Use my setup on a machine (first time) | `git clone https://github.com/genewebb/ai-setup.git` into the machine's repos root, then `install.ps1` |
| Get changes made elsewhere | `install.ps1` (git pull --ff-only + install) |
| Send changes from this machine | `publish.ps1 -Message "..."` (secret scan, commit, rebase, push) |
| Share an item at work | add it to `share.yaml`, run `tools\Promote-ToWork.ps1 -TargetRepo <work marketplace clone>` |

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

This repo is the source. `share.yaml` lists the skills and agents that are also published to a work plugin
marketplace. `tools\Promote-ToWork.ps1` copies them one way and refuses an item that:

- matches a `blockedPatterns` entry (personal accounts, hosts, personal paths, `[[memory]]` links)
- uses a machine-profile `{Key}` path
- references a private skill that is not promoted with it
- looks like it holds a secret

It never commits in the work repo. Coworkers get plugin-namespaced names (`/plugin:skill`); on my own machines
the private install keeps the bare names, so I do not install my own promoted plugins.

## Secrets

Never committed. `.gitignore` excludes the known shapes and `publish.ps1` runs `tools\Find-Secrets.ps1` on every
change; a hit blocks the commit. Machine secrets stay in `{SecretsDir}`.
