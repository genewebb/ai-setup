# prof: one hub for the PowerShell profile, the AI runtime and the machines that run them

Status: DRAFT for Gene's approval, 2026-10-17. Nothing built. Owner: Gene.

## 1. Why

Gene edits the profile, skills, memory and stream kit on the laptop and wants the same setup on other machines
for a named account, with each machine's own folder layout. Today that takes a chain of hand steps
(`publish.ps1`, log on there, clone, edit the machine profile, `install.ps1`, copy the Terminal settings) spread
over several commands whose names and switches are hard to remember. The profile already holds about forty
commands; the names are the problem, not the features.

Goal: **one short command, `prof` (long alias `manageProfile`), that moves the whole setup to or from any machine
and account, and can be driven from a menu when the switches are forgotten.** It works for any Windows machine
that has an admin share and WinRM; nothing in it is specific to one host. The first target is SMVMTR1 for
corp\agenewe. It also sets the pattern every later hub (deploy, streams, tab) follows, so the command count
shrinks instead of growing.

## 2. Decisions already made (Gene, 2026-10-17)

| Topic | Decision | Consequence |
|---|---|---|
| Name | `prof`. `mp` is already an alias in the profile. `manageProfile` stays as the long alias. | Hub names are short lowercase words: `prof`, `deploy`, `streams`, `tab`, `go`, `hubs`. |
| Transport | **Laptop is the hub.** Changes travel by `git push` straight into the target's clone over the admin share, then `install.ps1 -NoPull` runs there over WinRM. GitHub stays `origin` as backup and provenance; targets never fetch from it. **The laptop is the only machine that publishes to GitHub.** | No GitHub credentials on any target. The pushing machine must be on and reach the target's admin share and WinRM. Any other machine still holding a GitHub credential for this repo becomes a plain target when it is next used. |
| Accounts per machine | **One clone per user.** `AIWorkRoot`, `ClaudeHome`, memory junction and runtime are per account. | The machine profile's `AIWorkRoot` row must contain `%USERNAME%` or `%USERPROFILE%` on a machine with more than one account. |
| SMVMTR1, corp\speedmerchants | **Retired.** Its installed runtime and the pre-git corpus folder are archived under that machine's `{ArchiveRoot}`; SMVMTR1 runs Claude as corp\agenewe only. | `bootstrap -Retire` does the archiving (section 4.5). `machines.yaml` lists agenewe only. |
| Verbs in the first build | push, pull, status, check, bootstrap, terminal, secrets, help, config, edit, reload, show, plus a **menu** when no verb is given. | See section 4. |
| `terminal` under WinRM | **Settings-only `-ForUser` mode**: writes the user's Windows Terminal `settings.json`; shortcuts and the Windows Terminal install go to LEFT TO DO. | Small change to `AddOrUpdateMyTerminal.ps1`; works for a non-admin user. |
| Credentials for `-User` not equal to the caller | **Prompt every time** (`Get-Credential`). Same account = Kerberos, no prompt. | Nothing stored. Preflight tests WinRM **per user**, not per machine. |
| Parameter name | `-User`, not `-Profile`. "Profile" already means the PowerShell profile and the machine profile. | Default `-User` = the caller (`DOMAIN\name`). |
| Memory | One shared memory across machines and accounts (the 10/14 design: memory lives in the clone, `ClaudeHome\memory` is a junction into it). | Conflict rule in section 4.4 step 3, my call. |

## 3. What exists and is reused

- `install.ps1` at the clone root: pulls (skippable with `-NoPull`), installs the Claude runtime, memory
  junction, both PowerShell profile folders, own `Gene.*` modules, PSGallery modules, stream-host scripts and the
  scratch cleanup task. Every location comes from that machine's `C:\Deploy\Setup\ProfileMachineConfig.md`.
  `-Yes` makes it run with nobody at the keyboard; `-Check` reports only. It refuses when the clone it runs from is
  not the machine profile's `AIWorkRoot` (as expanded for the account running it).
- `publish.ps1`: commit everything, secret scan (`tools\Find-Secrets.ps1`), `pull --rebase`, push to GitHub.
- `setup\Export-AISecrets.ps1` + `install.ps1 -SecretsFile`: Claude secrets travel as one passphrase-encrypted file.
  The passphrase is asked by `Read-Host` inside `setup\Install-AIMcp.ps1`.
- The profile's `#region Machine config`: `Read-GeneMachineConfig` parses the first table of the machine profile;
  `Test-HelpRequested` / `Write-Usage` give every command its `-h`; `Import-GeneModuleOnce` lazy-loads a module.
- `lib\MachineConfig.psm1`: `Get-AIMachineProfile`, `Test-AIMachineProfile`, `Get-AIConfig`, the Git policy table.
- `setup\Clear-AIScratch.ps1 -Register`: registers a per-user scheduled task with an S4U principal (no password,
  works from a network logon). The pattern to reuse for anything that must run as the user outside WinRM.
- `AddOrUpdateMyTerminal.ps1` (today in `{PowershellScriptsDir}`, outside the repo): applies Windows Terminal
  settings for the admin account it runs as plus the account that owns the interactive desktop, relaunches itself
  under UAC, installs Windows Terminal when missing, writes Public-desktop shortcuts; `-Capture` refreshes the
  embedded settings from the live file.

Measured on SMVMTR1 on 2026-10-17 as corp\agenewe: WinRM answers (default endpoint is Windows PowerShell 5.1, no
`PowerShell.7` endpoint), pwsh 7.6.7 and git 2.56 installed, github.com reachable on 443 and 22 (not needed with
the laptop hub), work drive present, admin shares readable. No ai-setup clone anywhere; the machine profile's
`AIWorkRoot` still names the retired pre-git corpus folder; corp\agenewe has no PowerShell profile folder yet,
corp\speedmerchants has the old install. So SMVMTR1 for corp\agenewe is a **bootstrap with -Retire**, not a push.

## 4. The command

```text
prof <group> <command> [-Machine <name>] [-User <DOMAIN\name>] [switches] [-WhatIf] [-h]
prof <command> ...                 # a command only one group has: the group may be left out (prof push)
prof <group>                       # that group's menu
prof                               # main menu: the groups, then help
prof help [<group> [<command>]]    # help stays at the top level
long alias: manageProfile
```

**prof is the general-purpose hub (Gene, 10/17).** Commands live in groups; the main menu lists the groups. The
groups, in menu order: `streams` (the stream board, section 6.1), `setup` (the eleven commands below; it was named
`streams` until Gene renamed it 10/17 so `streams` could mean the board), `git`, `build`, `ai`, `other`. Other profile commands join as further groups
(section 6). A group is one entry in `$script:ProfGroups` (`Verbs.ps1`): its commands with one-line and long
descriptions, usage lines, the function prefix, which commands need `-Machine`, and the menu's question flow.

Groups and commands are tab-completed. Every verb accepts `-h` (the existing `Write-Usage` style) and `-WhatIf` (reports,
writes nothing anywhere). Every verb that runs prints the **composed command line** it is about to run before it
runs it, so a menu session teaches the syntax.

The `setup` group (`prof setup <command>`):

| Command | What it does | Needs |
|---|---|---|
| `push` | Laptop -> target: publish here, harvest the target's local edits, merge them here, push into the target clone, run `install.ps1 -NoPull -Yes` there as `-User`. | admin share + WinRM |
| `pull` | Target -> laptop: harvest + merge the target's edits here, then `install.ps1 -NoPull -Yes` here. Does not touch the target's installed files. | admin share |
| `status` | One table over every machine in `machines.yaml` (or `-Machine`): reachable, machine profile present, per user: clone present, HEAD, ahead/behind the laptop, dirty files, installed runtime revision, profile file in sync. Read-only, admin share only, no credentials. | admin share |
| `check` | Machine profile diff laptop vs target (rows missing on the target, rows pointing at paths that do not exist there, `AIWorkRoot` not per-user on a multi-user machine) plus `install.ps1 -Check` on the target as `-User`. Writes nothing. | admin share + WinRM |
| `bootstrap` | Cold machine or account: machine profile (create only if missing), `-Retire` of old accounts, clone, git config, ACL, first install; `-WithTerminal`, `-WithSecrets` chain the two verbs below. Ends with a LEFT TO DO list. | admin share + WinRM; caller admin on target |
| `terminal` | Write Windows Terminal settings for `-User` on the target (`AddOrUpdateMyTerminal.ps1 -ForUser`). | WinRM |
| `secrets` | Export Claude secrets here (passphrase typed), copy the file to the target scratch, `install.ps1 -NoPull -Yes -SecretsFile` there, delete both copies. | admin share + WinRM |
| `config` | Show the machine profile table: this machine, or `-Machine X`. Replaces `machinecfg`. | admin share for remote |
| `edit` | Open the **repo copy** of the profile (`{AIWorkRoot}\pwsh\PowerShell\...`) in the editor. Replaces `ep`, which opens the installed copy that the next install overwrites. | - |
| `reload` | `install.ps1 -NoPull -Yes` here, then `. $PROFILE`. Replaces `rp`. | - |
| `show` | Print the installed profile path and the repo copy path with their hashes (in sync or not). Replaces `sp`. | - |

`prof help` (top level, not in a group) lists every group and command, `prof help <group>` one group,
`prof help <group> <command>` (or `<command> -h`) one command in full, plus old name -> new command.

`-Machine` omitted = this machine (`config`, `edit`, `reload`, `show`, `status`); `push`, `pull`, `check`,
`bootstrap`, `terminal`, `secrets` require it. `-Machine` equal to this machine is refused for push/pull.

### 4.1 Menu

`prof` with no words:

1. pick a group (or help); `prof <group>` starts at step 2;
2. pick a command (one-line descriptions; the group's own help is the last entry);
3. the group's questions (setup: machine from `machines.yaml` or typed, account, switches as yes/no);
4. shows the composed command line (`prof setup push -Machine ...`), asks once, runs.

Prompts are `Select-GeneMenu`, `Read-GeneYesNo` and `Read-GeneText` (`Menu.ps1`), shared by every group. They
have two looks with the same answers. **Arrow keys** (up/down + Enter, a `(cancel)` entry, the default listed
first), like devutils' Spectre.Console prompts, through the PwshSpectreConsole module (PowerShell 7.4+, in
`pwsh\modules.txt`) when it is installed and a real console is attached. **Numbered** (type a number, Enter =
default, `q` = cancel) otherwise: no module, redirected input (remote runs), tests (`-Reader`), or
`$env:GENE_PLAIN_MENU` set.

### 4.2 Machines registry

`machines.yaml` at the clone root (the repo is private; `share.yaml` already blocks host names on promote):

```yaml
machines:
  SMVMTR1:
    users: [CORP\agenewe]
```

Only names and accounts live here; a machine typed at the prompt that is not listed is offered to be added.
Every path comes from the target's own machine profile, read over the admin share at the fixed convention path
`C:\Deploy\Setup\ProfileMachineConfig.md` (system drive assumed `C:`; a `systemDrive:` key per machine overrides
it). The machine running the command is never listed as a target.

### 4.3 Resolving the target's paths

1. Read the target's machine profile over the admin share and parse its first table exactly as
   `Read-GeneMachineConfig` does (refactor that function to take `-Path` and `-PassThru` so the profile and the
   module share one parser).
2. Open one WinRM session as `-User` (reused for the whole verb). In it, expand `AIWorkRoot`, `ClaudeHome`,
   `ScratchRoot`, `ArchiveRoot` with that user's environment and return `$PROFILE`'s folder and the Documents
   folder. Never guess the Users folder from the account name: the real profile folder may differ.
3. Admin-share form of a target path: drive letter becomes `\\<Machine>\<letter>$\` plus the rest of the path.
   Git addresses the clone that way for fetch, push, add and commit; it is a few megabytes, so UNC speed is fine.
4. `status` has no session (no credentials): it expands `%USERPROFILE%` to the Users folder under the system
   drive share and `%USERNAME%` to the name, and marks the row `unresolved` when the folder is not there instead
   of failing.

### 4.4 push, step by step

**Where git runs.** Worktree commands (status, add, commit, the fast-forward) run ON the target, in the WinRM
session, as `git -c safe.directory=* -C <local path>`. Only object transfer crosses the share: the laptop fetches
from the target clone and pushes to the side ref `refs/prof/incoming`. Measured on SMVMTR1: `git status` over the
share took 40 s on the 1,400-file clone (every run re-hashes the index the other machine wrote); in the session it
is instant. This replaces the first draft's UNC worktree commands and `receive.denyCurrentBranch=updateInstead`.

Order matters: the laptop rebases on GitHub **before** it takes the target's commits, so nothing harvested is ever
rewritten and the push into the target is always a fast-forward.

0. Preflight (also what `-WhatIf` prints): machine profile readable, `AIWorkRoot` row present and per-user when the
   machine lists more than one account, clone present at the target `AIWorkRoot` (else "run bootstrap"), WinRM
   session opened as `-User`, the clone is on `main`.
1. `publish.ps1` here: commits laptop changes (secret scan, one confirmation), `pull --rebase` on GitHub, push. A
   GitHub failure (VPN, credentials) is a **warning**, not a stop: the commit exists locally and the target is the
   goal.
2. Harvest the target: if its tree is dirty (memory files from Claude sessions there), run `Find-Secrets.ps1`
   over those files (read through the share), then `add -A` and commit in the session as
   `prof: <Machine>\<User> local changes`.
3. Merge the target into the laptop: `git fetch <unc> main`, then `git merge --no-edit FETCH_HEAD`. Memory index
   files (`memory\MEMORY.md`, `memory\index_*.md`) are rewritten on both sides in normal use, so they get
   `merge=union` in `.gitattributes` (my call: both sides' index lines survive, Claude tidies duplicates at its
   next write). Any other conflict stops with the file list and the three commands to resolve it; nothing else
   has changed.
4. `git push <share url> +HEAD:refs/prof/incoming` (objects only; the target's work tree is not touched), then
   `git merge --ff-only refs/prof/incoming` in the session. A live Claude session that wrote memory after step 2
   only blocks this when it touched a file the update changes: git refuses, nothing changed there, run push again.
   An unrelated uncommitted file stays as it is (test "push fast-forwards past an unrelated uncommitted file").
5. `git push origin` here, plain, best-effort (the merge commit from step 3). Refused only if GitHub moved since
   step 1, which the summary reports as "publish again later".
6. Remote `pwsh -NoProfile -File <AIWorkRoot>\install.ps1 -NoPull -Yes` as `-User`, output streamed, exit code kept
   (0 ok, 2 invalid machine profile, 3 drift: say so, same meaning as a local run). `-WhatIf` runs it with `-Check`.
7. Summary: commits moved each way, install summary lines, "open a new pwsh on <Machine> (or run `prof reload`
   there)".

`pull` = steps 0, 2, 3, then `install.ps1 -NoPull -Yes` here. Its session runs as the caller (Kerberos, no prompt),
because nothing there needs to run as `-User`. `push` includes everything
`pull` does, so one run brings both sides level.

### 4.5 bootstrap, step by step

For `-Machine M -User U`; `-WorkDrive D:` (default `C:`) seeds the paths of a new machine profile;
`-Retire <DOMAIN\name>[,...]` names old accounts on M whose install is archived.

1. **Machine profile.** Missing: write one from the laptop's, rewriting the laptop work root to `<WorkDrive>`,
   setting `AIWorkRoot` to the per-user convention `<WorkDrive>\devops\%USERNAME%\ai-setup` (my call; any row Gene
   edits afterwards is what the tool reads), clearing the Status column to `unverified`. Present: **never
   overwritten**. Rows the laptop has and the target lacks, and an `AIWorkRoot` that is not per-user on a
   multi-user machine, are printed as the exact lines to add or change; `-FixProfile` applies them (adds rows
   with a blank value, replaces `AIWorkRoot`), after showing a diff and asking. Because the file is machine-wide,
   changing `AIWorkRoot` changes it for every account on that machine: the verb lists the other accounts that have
   an installed runtime there (`ClaudeHome` under their Users folder) and refuses `-FixProfile` until each is
   either bootstrapped in the same run or named in `-Retire`.
2. **Retire** each `-Retire` account: show what will move (its `ClaudeHome` runtime, its PowerShell profile folders,
   the old `AIWorkRoot` folder when it is not a git clone), ask once, then **move** (never delete) them to
   `{ArchiveRoot}\ai-retire-<stamp>\<account>\` on M and unregister that account's "AI scratch cleanup" task.
   Memory found in the old runtime is merged into the laptop clone first, the same way `install.ps1` step 3 merges
   a real memory folder before it links. Then U's rows can be fixed.
3. **Session** as U; expand paths; create the parent folders.
4. **Clone**: `git bundle create` of `main` on the laptop, copied to the target's `{ScratchRoot}\prof\`, then
   `git clone -b main <bundle> <AIWorkRoot>` in the U session (the session cannot reach back to the laptop: second
   hop). The clone is written by U, so it belongs to U: no ACL or `safe.directory` step. Then on the target clone:
   `remote set-url origin` to the GitHub URL, `user.name` / `user.email` copied from the laptop clone; the
   `.gitattributes` union rule travels with the clone. Both bundle copies are deleted. U must be remotable
   (Administrators or Remote Management Users on M); the session check says which group otherwise.
5. (folded into 4)
6. **Install**: remote `install.ps1 -NoPull -Yes` as U (same as push step 6).
7. `-WithTerminal` -> `terminal`; `-WithSecrets` -> `secrets`.
8. **LEFT TO DO** printed: sign in to Claude as U on M (`ai`), MCP secrets if `-WithSecrets` was not used,
   Chocolatey tools from the install notes, Windows Terminal shortcuts and the Windows Terminal install itself
   (section 4.6), anything `install.ps1` reported as not installed.

### 4.6 terminal and secrets

- `AddOrUpdateMyTerminal.ps1` moves into the repo (`setup\`), so `install.ps1` carries it to every machine and
  the verb runs the installed copy on the target as `-User`. It gains a `-ForUser` mode that writes only the
  calling user's Windows Terminal `settings.json` (the embedded settings, same merge rules as today) and skips
  elevation, the desktop-account lookup, the Windows Terminal install and the shortcuts. Those are LEFT TO DO
  lines when the verb finds Windows Terminal missing or the shortcuts absent. Console behaviour of the script is
  unchanged.
- `secrets`: `Export-AISecrets.ps1 -Out <laptop ScratchRoot>\prof\secrets-<M>-<U>-<stamp>.bin` (passphrase typed
  twice here), copy to `<target ScratchRoot>\prof\`, remote `install.ps1 -NoPull -Yes -SecretsFile <that path>`.
  The remote install is a child `pwsh` started from a 5.1 session, so a SecureString cannot cross into it and the
  command line and environment are logged; **the passphrase goes to the child's stdin** (my call). The builder
  verifies that `Install-AIMcp.ps1`'s `Read-Host` reads redirected stdin; if not, `install.ps1` and
  `Install-AIMachine.ps1` gain `-PassphraseFromStdin`. Never on disk, never in a process argument. Both files are
  deleted at the end, also on failure.

### 4.7 The git and build groups (Gene, 10/17)

`prof git status|push|pull [<repo>]` acts on the current branch of the repo you stand in, or of `<repo>`: a repo
from this machine's profile by folder name (every `*Repo` key plus `AIWorkRoot`), or a folder path. Naming a repo
moves the window into it and leaves it there. `push` is gpush (`Git-QuickPush` in Gene.GitTools: add, secret-name
guard, commit with `-Message`, default "Update latest", push with upstream); `pull` is `git pull --ff-only` and
stops rather than merging; `status` fetches, then shows `git status -sb` and ahead/behind in words. The menu offers
`(this folder)` first, then the known repos.

`prof build compile|run|publish|more <product>` drives the dp* commands in the profile, for products speed
(dpspeed), crewchief, datagen, mutate, speedy (dpv2) and all (dpall; publish and compile only). prof
moves the window into the product's repo and leaves it there.

| Command | Does |
|---|---|
| `compile` | Build only: `dotnet build` of the product's solution (`-Configuration`, Debug by default); `all` = the four speed-merchants solutions. New; no dp* did this. |
| `run` | The dp* command with no switches (build + publish + start; dpv2 = rebuild local containers). |
| `publish` | dp* `-Package`; `-Bump None|Patch|Minor|Major` maps to `-Bump`/`-BumpMinor`/`-BumpMajor`. The menu shows current -> new version. |
| `more` | The dp* command with any of its own switches; the menu lists them (from the function's parameters and help lines). |

Words prof does not know after the product are passed to the dp* command (`prof build run speed -CleanBuild`,
`prof build publish all -Products speed,crewchief -Parallel`); a switch the dp* command does not have is refused.
The menu runs product first, then action (Build only / Build + run / Publish / More options...), then the action's
questions. The dp* commands themselves are unchanged and still work.

A group sets `TopicParam` (the third word: Repo for git, Product for build), `TopicNames` (its tab completion) and
optionally `Menu` (its own question order instead of command list + Ask). `prof push`, `pull` and `status` now name
two groups, so prof asks which; `prof publish` still works alone.

### 4.8 The other group (Gene, 10/17)

`prof other` is a catalog, not a launcher: every remaining profile command by category (navigate, tabs, build, git,
board, profile, claude, tools) with what it does, how to call it, and the prof command that covers it where there is
one. `prof other <category>` lists one category, `prof other <category> <command>` shows one command; the menu
browses category, then command, and runs nothing. The catalog is `$script:ProfOtherCatalog` in `OtherGroup.ps1`; a
census test fails when the profile gains a lower-case top-level function the catalog does not list, so a new command
must be catalogued (or folded into a group) before the tests pass.

## 5. Where the code lives

- New module `pwsh\PowerShell\Modules\Gene.Profile\` (`.psd1` + `.psm1`), exporting `prof` (`Invoke-GeneProf`),
  `Select-GeneMenu`, `Get-GeneMachines`, `Resolve-GeneMachineTarget`. `install.ps1` step 4 already copies `Modules\`.
- The profile keeps a four-line stub: `function prof { Import-GeneModuleOnce Gene.Profile; Invoke-GeneProf @args }`
  plus the `manageProfile` alias and the argument completer for verbs. Profile load time does not grow.
- `sp`, `ep`, `rp`, `machinecfg` become one-line wrappers that print `use: prof <verb>` once and call it. Removal
  is a later decision.
- `Read-GeneMachineConfig` gains `-Path` / `-PassThru`; nothing else in the profile changes.
- `machines.yaml` at the clone root; `powershell-yaml` is already in `pwsh\modules.txt`.
- `.gitattributes` at the clone root with the union rule for the memory index files.
- `setup\AddOrUpdateMyTerminal.ps1` (moved in, `-ForUser` added); the copy in `{PowershellScriptsDir}` is removed
  once the moved one is installed everywhere.
- Tests: `pwsh\PowerShell\Modules\Gene.Profile\tests\` with a fake machine profile, a bare "target" clone on a
  local path standing in for the admin share, and the push/pull algorithm run against it (no network), including
  a both-sides-edited `MEMORY.md`. `Test-NoHardPaths.ps1` keeps passing (`pwsh\*` is allow-listed; `machines.yaml`
  holds names, not paths).

## 6. Consolidation beyond prof (direction, not in this build)

**Superseded 10/17 by Gene:** prof is the one general-purpose command, with groups, instead of one hub per domain.
The menu stays two levels (group, command) plus the command's questions. Each row below becomes a group of prof
as it is built (same skeleton: commands + completer + `-h` + menu questions + composed command echo); old names
stay as aliases.

| Group (later) | Folds in | Note |
|---|---|---|
| `setup` | sp, ep, rp, machinecfg, profile/runtime/machine moves | built: the eleven commands of section 4 (named `streams` until 10/17) |
| `build` | dpspeed, dpcrewchief, dpdatagen, dpmutate, dpall, dpv2, dpContainers | built 10/17, section 4.7; `containers` is Speedy only |
| `git` | gpush, pps, psql, pushrules | built 10/17, section 4.7; the scripts folders are repos in its list, `-AIOnly` = pushrules |
| `ai` | dpAI | built 10/17: `prof ai local|remote|git|promote [<repo>]`, the mode is the command |
| `streams` | addStreams, addStreamTab, stopStreams, removeStreamTab, rerunStreamTab, getStreams, pushStreams, updateStreams | built 10/17 as a thin layer (section 6.1): `prof streams add|tab|stop|remove|rerun|get|push|update|status-rebuild` call the profile commands; `-WhatIf` becomes `-DryRun` |
| `tab` | addtab, addnew, addLinux | |
| `go` | cdevops, caiprof, cspeed, ccrew, cpower, csql, ccursor | `go speed`, repo names from the machine profile |
| (none) | `prof help` lists every group and every old name with its new form | the one name to remember is `prof` |

Old names stay as aliases for a deprecation period; `hubs` and `<hub> help` show the mapping. Each hub moves into
its own `Gene.*` module as it is built, which also shortens the 4,400-line profile.

### 6.1 The `streams` hub: the 10/17 stream-commands proposal, re-based on the laptop hub

**Built 10/17 (thin layer):** `StreamsGroup.ps1` maps each board command to its profile function (the table below is the
target behaviour of those functions, not yet re-based). `status-rebuild` is new: it sets the LastWriteTime of
`<SpeedyRepo>\.streams\inbox\stream-status.md` to now so the Status runner's next tick rebuilds the status page;
`-Repo` overrides the repo. Below, `prof reload` / `prof pull` mean `prof setup reload` / `prof setup pull`.

The getStreams / pushStreams / updateStreams proposal (decisions: owner-push column in the Git policy table that
only the stream push reads; host guard = `.streams\host.json` board marker, no profile key; `-Force` to override)
stands, with two changes forced by "no GitHub credentials on targets":

| Proposed | Becomes | Change |
|---|---|---|
| `getStreams` | `streams get` | Was: ai-setup clean check + `install.ps1` (pulls GitHub) + `git pull --ff-only` SpeedyRepo. Now: `prof reload` (install what the local clone holds, no pull) + the SpeedyRepo pull + the long-tab list. The kit reaches a host only by `prof push -Machine <host>` from the laptop. |
| `pushStreams [-Message]` | `streams push` | Was: `publish.ps1` then push the stream branch. Now: commit the kit and memory edits locally (so the laptop's next `prof pull` harvests them), then push the stream branch where owner-push allows. `publish.ps1` runs on the laptop only. |
| `updateStreams [-Code] [-RestartSessions]` | `streams update` | Unchanged, except the kit install step is `prof reload`. |
| `pushStreams -Handoff` (old host B) | `streams push -Handoff` | Stop all, wait quiet, commit locally, push code. No publish. |
| `getStreams -FromHost B` (new host A) | `streams get -FromHost B` | Adds a first step: `prof pull -Machine B -User <B's account>` so B's kit and memory edits land on A before the board mirror. Then as proposed: read B's SpeedyRepo from B's machine profile over the share, check quiet + trees match, back up A's board to `{ScratchRoot}`, mirror, write `host.json`, mark B MOVED, readiness checks, LEFT TO DO. |
| addStreams, addStreamTab, stopStreams, removeStreamTab, rerunStreamTab | `streams add`, `streams tab`, `streams stop`, `streams remove`, `streams rerun` | Same code, moved into the hub; `-Repo` defaults to SpeedyRepo as proposed. |

Division of labour: `prof` owns the ai-setup clone, the installed runtime and the profile on every machine and
account; `streams` owns the board, the stream code branch and the tabs, and calls `prof` for anything kit-shaped.
Nothing about the kit's transport is implemented twice.

`-FromHost` reads B's machine profile over the share the same way `prof` does (section 4.3), so the parser
refactor serves both. The owner-push column lands in `lib\MachineConfig.psm1`; every other reader of the Git
policy table (`git-guard`, `install.ps1`'s location list, `Test-AIMachineProfile`) must tolerate the new column,
which the builder checks.

Build order: `prof` first (this design), `streams` second (its own short design once this one is live), because
`streams get`, `update` and `-FromHost` call into it.

## 7. Non-goals and anti-goals

- Not a scheduler: nothing runs on its own. Gene runs `prof push` when he wants a machine updated.
- Never edits an existing machine profile without `-FixProfile` and a shown diff. Never writes the Status column
  as truth.
- Never deletes an old install: `-Retire` moves to `{ArchiveRoot}` after showing the list and asking.
- No credentials stored anywhere. No GitHub credentials on targets.
- Does not move product repos, Chocolatey tools, Claude sign-in or app secrets (TestAuto, CrewChief JSON).
- A failure in the middle leaves both clones valid git repos with every commit intact; the only partial state
  possible is "target installed from an older commit", which the next push fixes.

## 8. Risks the builder must verify

1. `git` fetch/push against a UNC path (objects only; `-c safe.directory=*` on each call). Worktree commands run in
   the session (40 s `git status` over the share, measured).
2. `install.ps1` under WinRM: `$PROFILE` folder resolution in a 5.1 remote session that launches `pwsh -NoProfile
   -File`; `Register-ScheduledTask` with S4U from a network logon; `Install-AIMachine.ps1` without a console;
   `Read-Host` on redirected stdin for the passphrase.
3. The in-session `merge --ff-only` when the target's memory junction is written during the push (expected: refused
   only when the same file changed, reported, nothing changed).
4. Second hop: nothing in the remote steps may touch a share or the laptop.
5. `merge=union` on the memory index files: no line loss, duplicates only.
6. Moving another account's `ClaudeHome` while that account has no session open (the retire step checks for
   running Claude processes of that account first and refuses if any).

## 9. Left to the builder

Exact menu wording, table layouts, colours, test fixture shapes, the completer implementation, error text,
how `status` detects the installed runtime revision (what `Install-AIMachine.ps1` writes into `ClaudeHome`), the
order of the LEFT TO DO list, and how `machines.yaml` records a machine added from the prompt.
