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
pwsh -NoProfile -File .\install.ps1
pwsh -NoProfile -File .\publish.ps1 -Message "stream-author: tighten ticket clauses"
```

A conflict is an ordinary git conflict: resolve, `git rebase --continue`, re-run `publish.ps1`.

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
