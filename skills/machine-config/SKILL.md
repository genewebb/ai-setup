---
name: machine-config
description: Machine-portable AI configuration for this machine - installs the corpus runtime, generates settings.json from the machine profile (ProfileMachineConfig.md) and the shared permissions.yaml, reports drift, and harvests clicked approvals back into shared policy. Use for /machine-config apply, /machine-config check, /machine-config harvest, /machine-config show, or when a skill path {Key} does not resolve, a session says it was not started with 'ai', or an apply stopped on drift.
---

# machine-config

Every machine-specific value lives in ONE file, the machine profile `ProfileMachineConfig.md` (location:
`AI_MACHINE_CONFIG` if set, else the convention path). The corpus (`{AIWorkRoot}`) holds everything shared. The
installer copies the corpus runtime into `{ClaudeHome}` and generates `settings.json`; the `ai` launcher runs the same
installer before every session, so a normal start is always current.

Scripts are installed in `{ClaudeHome}\bin`. Run them with `pwsh -NoProfile -File`.

## Arguments

| Argument | Run | Writes |
|---|---|---|
| `show` | `Show-AIMachine.ps1` | nothing |
| `check` | `Install-AIMachine.ps1 -Check` | nothing |
| `apply` | `Install-AIMachine.ps1 -WhatIf`, show the diff, then `Install-AIMachine.ps1` | runtime, settings.json, state |
| `harvest` | `Invoke-AIHarvest.ps1` (see below) | the harvest record; permissions.yaml only on a global accept |
| (none) | treat as `check` | nothing |

### show
Prints resolved paths (with local / share / disconnected), resource write routes, the Claude access list, the git
policy and the MCP servers, plus profile validation problems. Relay it as is.

### check
Reports invalid profile rows, unavailable resources, drift (installed files or owned settings edited by hand),
pending approvals, repo `.claude\` folders (a `settings.local.json` is "pending harvest"; anything else breaks the
no-`.claude`-in-repos rule) and the hard-path gate summary. Exit code 0 = clean.

### apply
1. Run `-WhatIf` first. Show the user the settings diff and the file list from the report it names.
2. Run the apply. Exit codes:
   - `0` applied (or already current);
   - `2` validation failed: show the diagnostic, change nothing, ask the user to fix the profile row it names;
   - `3` drift: the edited files are copied to a `drift-<stamp>` folder and new permission rules are queued for
     harvest. Show the list. Re-run with `-AcceptDrift` only after the user confirms (or after a harvest).
3. Relay the "needs a fresh launch" list: hooks, env and permissions take effect in a NEW session started with `ai`.

### harvest
Clicked "always allow" approvals land in a repo's `.claude\settings.local.json` or in the live settings. Harvest
promotes the ones the user wants into the shared `permissions.yaml`, written with `{Key}` paths.

1. `Invoke-AIHarvest.ps1` (propose). Shows a table: id, status, tier, scope, rule, proposed `{Key}` form.
   - `covered`: the generated policy already allows the same operation in the same tier. Nothing to do.
   - `conflict`: a generated deny contradicts it (for example an edit under a read-only folder). Never promote it
     without asking.
   - `proposed`: open. Path containment by a DIFFERENT tool never covers an approval.
2. Ask the user with AskUserQuestion, per item or in groups, with a recommendation: global (shared, all machines),
   keep (stays in its repo or user scope), or reject. Repo scope is the default.
3. `Invoke-AIHarvest.ps1 -Action accept -Id <ids> -Global`, `-Action accept -Id <ids>` (keep), or
   `-Action reject -Id <ids>`.
4. After a global accept: run apply, then `Invoke-AIHarvest.ps1 -Action finalize`. Finalize removes an original
   entry only when its rendered replacement is in the installed settings; unrelated local settings stay.

## Rules
- Never hand-edit `{ClaudeHome}\settings.json` owned properties (permissions, hooks, statusLine, the `AI_*`, `TEMP`,
  `TMP`, `CLAUDE_CODE_TMPDIR` env keys, `cleanupPeriodDays`). Change the profile or the corpus, then apply.
- The corpus `{AIWorkRoot}` is a local clone of the private `ai-setup` git repo. Edit a shared file there directly,
  never in `{ClaudeHome}`. Send changes with `{AIWorkRoot}\publish.ps1`; take changes made elsewhere with
  `{AIWorkRoot}\install.ps1` (git pull + this installer + memory, PowerShell and stream-host). Git replaces the old
  machine-sync and Q: publish routes. A vault folder is still written through the Obsidian API
  (`Write-AIFile.ps1`), never directly.
- Machine values never go into shared files. A new machine path is a new profile key; refer to it as `{Key}`.
- `Test-NoHardPaths.ps1 -Root {AIWorkRoot}` must report 0 before a corpus change is published.
