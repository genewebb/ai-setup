# prof setup share Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `prof setup share` publishes the picked PowerShell commands and the picked Claude skills into the coworker repo (`{ShareRepo}`, ADO speed-merchants-dba) under `ai\` plus a root plugin marketplace, replacing `prof setup export` and `tools\Promote-ToWork.ps1`.

**Architecture:** Hub module `Gene.Profile` gains `Share.ps1` (profile half, already written on this branch by an earlier session: offer, repo state, pick, AST closure, key questions, trim, stage, scans, write, README) and `ShareSkills.ps1` (skills half: category, offer, state, pick, hard-stop checks, reference rewrite, plugin.json + marketplace.json, write). `SetupGroup.ps1` wires the `share` verb where `export` was. `pwsh\Install-Profile.ps1` is reworked for the coworker (reads `ai\profile`, prompts per blank key, no 5.1 profile) and is copied into every share. Neither Share file ever ships.

**Tech Stack:** PowerShell 7, PowerShell AST (`System.Management.Automation.Language`), git CLI, `powershell-yaml` (share.yaml), `tools\Find-Secrets.ps1`, test harness `setup\tests\TestHarness.ps1` (`Test-Case`, `Assert-*`, `New-TestRoot`, `-Reader` answer queues). Claude Code plugin format per the official docs fetched 2026-10-23 (marketplace.json: `name`, `owner.name`, `plugins[]{name, source "./path", description}`; plugin.json: `name` required, `version` free string, `metadata` allowed, `skills/` auto-discovered; validator `claude plugin validate <dir>`).

**Spec:** `Q:\Work\Work\99_Frequent\Profile\Share Design.md` (vault; sections 2, 3, 5, 6, 7). Branch `work/prof-share` cut from main d8625b6.

## Global Constraints

- The share writes only `<repo>\ai\**`, `<repo>\.claude-plugin\marketplace.json` and at most one pointer line in `<repo>\README.md`; any other changed tracked file is a thrown error (spec 5.1). Darias's files are never touched.
- share never runs `git commit` or `git push`; it prints the commands (spec 2). Claude never commits in the dba clone (git policy row `{ShareRepo}`: commit no, push no).
- Secrets (Find-Secrets.ps1 hit) = throw, nothing written. blockedPatterns hits = list, one yes/no (spec 2). `{Key}` token in a picked skill = throw. `[[unpicked skill]]` = throw (spec 5.4).
- Never offered or shipped: `board` category, `sp`, `ep`, SetupGroup/StreamsGroup/Target/Sync/Export/Share*.ps1, the WindowsPowerShell 5.1 profile, agents, commands, hooks, settings, memory (spec 2).
- Shipped core: every `$global:GeneMachineDefaults` value emptied (spec 4.1). Only `PowerShell`-edition rows of modules.txt ship.
- Skill category = first hyphen token of the name when 3+ hub skills share it, else `general`; front-matter `category:` overrides (spec 5.4). Plugin name = category; coworker invokes `/<category>:<skill>`.
- Rewrite happens in the copy only; the hub source is never edited (spec 5.4).
- Tests use fixture hubs and temp git clones under `New-TestRoot`; no test touches the real dba clone, the real profile folder or `C:\Deploy\Setup`.
- No hard paths in repo code (`setup\Test-NoHardPaths.ps1` stays exit 0); no binary check-ins; conventional commits with the attribution trailer.
- Every change-1 suite stays green: `Prof.Tests.ps1`, `ProfileSplit.Tests.ps1`, `StreamSync.Tests.ps1`, `ScratchClean.Tests.ps1`, `Test-NoHardPaths.ps1`.

## Review Focus

1. A skill folder holding files other than SKILL.md (scripts, .json, .png): copied byte-for-byte except `.md`, which is rewritten; a `.png` must not be read as text. Test in Task 5.
2. A `/name` in a skill that is a Claude built-in or plugin command (`/plugin`, `/loop`, `/clear`) and not a hub skill: left alone, no stop. Test in Task 5.
3. `[[name|alias]]` and `[[name#heading]]` wiki forms: the skill name is the part before `|` or `#`; rewritten to `<category>:<name>` (alias text dropped). Test in Task 5.
4. Unpicking every skill of a category: `ai\plugins\<category>` removed and its marketplace entry gone; an empty `plugins` array is still valid JSON. Test in Task 6.
5. Installer against an existing `ProfileMachineConfig.md` that already has the key with a blank value: the row is kept (not asked again, not duplicated), only missing keys are appended. Test in Task 3.

---

### Task 1: Commit the profile half as it stands

The earlier session wrote `Share.ps1` (841 lines) and `Share.Tests.ps1` (30 cases, all passing at 16:57 today) but never committed them. This task reviews and commits them unchanged, so later tasks have a BASE.

**Files:**
- Commit: `pwsh/PowerShell/Modules/Gene.Profile/Share.ps1`, `setup/tests/Share.Tests.ps1`, `lib/MachineConfig.psm1` (ShareRepo in `$script:AIKeys`), `pwsh/PowerShell/Microsoft.PowerShell_profile.ps1` (ShareRepo in `$global:GeneMachineAIKeys`).

**Interfaces:**
- Produces (used by every later task): `Get-GeneShareRepo [-Repo]`, `Assert-GeneShareRepo -Repo`, `Get-GeneShareProfileDir -Repo`, `Get-GeneShareState -Repo` ({Categories, Keys, Manifest}), `Resolve-GeneShareClosure -Hub -Picks [-Offer]`, `Get-GeneShareStageRoot`, `Get-GeneShareBlockedPatterns [-Hub]`, `Find-GeneShareMentions -Root -Patterns`, `Find-GeneShareSecrets -Hub -Root`, `Test-GeneShareScans -Hub -Root [-Ask] [-Reader]` (count or $null), `Add-GeneShareRootPointer -Repo`, `Show-GeneShareGitCommands -Repo -Message`, `Get-GeneShareReadmeText -Repo -Owner`, `Invoke-GeneShareProfile [-Repo] [-WhatIf] [-Reader]`, `Invoke-GeneProfShare [-What] [-Repo] [-WhatIf] [-Reader]` (dispatches `ai-setup` to `Invoke-GeneShareAiSetup` when defined), `$script:ShareNeverCategories`, `$script:ShareProfileRel = 'ai\profile'`, `$script:ShareManifestName = 'prof-share.json'`.
- Ledger note: this code was not written test-first in this session; the 30 cases are the acceptance evidence.

- [ ] **Step 1: Run the suite as evidence**

Run: `pwsh -NoProfile -File setup\tests\Share.Tests.ps1`
Expected: last line `30 passed, 0 failed`

- [ ] **Step 2: Commit**

```bash
git add pwsh/PowerShell/Modules/Gene.Profile/Share.ps1 setup/tests/Share.Tests.ps1 lib/MachineConfig.psm1 pwsh/PowerShell/Microsoft.PowerShell_profile.ps1
git commit -m "feat(prof): share profile half: offer, pick, closure, keys, trim, scans, write (Share.ps1)"
```

---

### Task 2: Wire `share` into the hub, retire `export`

**Files:**
- Modify: `pwsh/PowerShell/Modules/Gene.Profile/Gene.Profile.psm1` (`$geneProfOrder`: replace `'Export.ps1'` with `'Share.ps1', 'ShareSkills.ps1'`; comment line 4 names `Share`).
- Modify: `pwsh/PowerShell/Modules/Gene.Profile/SetupGroup.ps1`: `$script:ProfVerbs` `export` row (line 16) becomes `share = 'Hand picked commands and Claude skills to a coworker through the shared git repo (ai\ in speed-merchants-dba)'`; `$script:ProfDetails` `export` block (line 69) becomes a `share` block (profile | ai-setup | help; repo = the ShareRepo row, -Repo overrides; -WhatIf writes nothing); `$script:ProfUsage` (line 90) `share = 'prof setup share [profile | ai-setup | help] [-Repo <clone>] [-WhatIf]'`; the verb wrapper that called `Invoke-GeneProfExport` is dropped (Invoke-GeneProfShare lives in Share.ps1 and takes `-What` from the first word); `Read-GeneSetupMenuParams` `'export'` branch (line 824) becomes `'share'`: `Dry run only (-WhatIf)?` then `Read-GeneText 'Repo clone (Enter = the ShareRepo row)'`.
- Modify: `pwsh/PowerShell/Modules/Gene.Profile/Share.ps1`: new `Get-GeneShareOwner -Repo` (`git -C $Repo config user.name`, trimmed; fallback `Get-GeneCaller`); `Write-GeneShareProfile` and `Get-GeneShareReadmeText` use it instead of `Get-GeneCaller`, so the template's `set by <owner>` and the README never carry the account name that blockedPatterns flags on every share.
- Delete: `pwsh/PowerShell/Modules/Gene.Profile/Export.ps1`.
- Modify: `setup/tests/Prof.Tests.ps1`: dot-source list swaps `Export.ps1` for `Share.ps1`; verb list assertion (line 384) ends `'show', 'share'`; the export block (lines 417-452) is deleted; new cases below.
- Modify: `setup/tests/Share.Tests.ps1`: one case for the owner rule.
- Modify: `docs/manageprofile-design.md` line 102: the `export` row becomes the `share` row (one sentence, points at the vault design note).

**Interfaces:**
- Consumes: Task 1 `Invoke-GeneProfShare`.
- Produces: verb `share` reachable as `prof setup share [profile|ai-setup|help] [-Repo] [-WhatIf]` and from the setup menu; `Get-GeneShareOwner -Repo` (string).

- [ ] **Step 1: Write the failing tests** (Prof.Tests.ps1, after the `show` cases)

```powershell
Test-Case 'setup verbs: share replaces export' {
    $v = @($script:ProfGroups['setup'].Verbs.Keys)
    Assert-True ($v -contains 'share') 'share missing'
    Assert-True ($v -notcontains 'export') 'export still listed'
    Assert-Match $script:ProfUsage['share'] 'prof setup share \[profile \| ai-setup \| help\] \[-Repo <clone>\] \[-WhatIf\]'
}
Test-Case 'setup menu: share asks dry-run and repo' {
    $p = Read-GeneSetupMenuParams -Verb 'share' -Reader (New-Queue @('y', 'C:\x\dba'))
    Assert-Equal $true $p.WhatIf; Assert-Equal 'C:\x\dba' $p.Repo
}
Test-Case 'prof setup share help prints the help and returns nothing' {
    $out = Invoke-GeneProf setup share help 6>&1 | Out-String
    Assert-Match $out 'prof setup share profile'
    Assert-Match $out 'Never shared'
}
```

(Share.Tests.ps1)

```powershell
Test-Case 'owner: git user.name of the repo, never the account name' {
    & git -C $clone config user.name 'Test Owner'
    Assert-Equal 'Test Owner' (Get-GeneShareOwner -Repo $clone)
}
```

- [ ] **Step 2: Run both suites, verify they fail**

Run: `pwsh -NoProfile -File setup\tests\Prof.Tests.ps1`; `pwsh -NoProfile -File setup\tests\Share.Tests.ps1`
Expected: the four new cases FAIL (`share` not in verbs; `Get-GeneShareOwner` not recognized); the export cases still pass.

- [ ] **Step 3: Implement** the SetupGroup/psm1/Share.ps1 edits listed under Files; delete Export.ps1; delete the export test block; rewrite the docs row.

- [ ] **Step 4: Run the suites, verify they pass**

Run: Prof.Tests.ps1, Share.Tests.ps1, ProfileSplit.Tests.ps1, `setup\Test-NoHardPaths.ps1`
Expected: Prof `85 passed, 0 failed` (84 - 2 export + 3); Share `31 passed`; ProfileSplit `9 passed`; gate exit 0.

- [ ] **Step 5: Commit**

```bash
git add -A -- pwsh/PowerShell/Modules/Gene.Profile setup/tests/Prof.Tests.ps1 setup/tests/Share.Tests.ps1 docs/manageprofile-design.md
git commit -m "feat(prof): setup share verb replaces export; owner from git user.name"
```

---

### Task 3: Coworker installer

**Files:**
- Rewrite: `pwsh/Install-Profile.ps1` (keep the hash-compare copy loop and the modules step; drop the WindowsPowerShell branch and `-SkipWindowsPowerShell`; add the key prompts).
- Create: `setup/tests/InstallProfile.Tests.ps1`.

**Interfaces:**
- Consumes: the `ai\profile` layout from Task 1 (`PowerShell\`, `modules.txt`, `ProfileMachineConfig.md` template with columns `Key | Value | Used by | Status`, `prof-share.json`).
- Produces: `Install-Profile.ps1 [-ProfileDir <folder>] [-ConfigPath <file>] [-SkipModules] [-NonInteractive] [-Force] [-WhatIf]`. `-ProfileDir` defaults to `Split-Path $PROFILE.CurrentUserCurrentHost` (tests pass a temp folder). Exit code 0; prompts through `Read-Host` only (so a test feeds answers on stdin).

Behaviour (spec 5.5):
1. Copy `PowerShell\` into `-ProfileDir` by hash; back up replaced files to `%TEMP%\profile-install-<stamp>\`; print `N file(s) updated`.
2. Install missing `PowerShell` rows of `modules.txt` (unchanged logic, no 5.1 rows).
3. Config: parse the template rows. No existing file: for every row with a blank Value and not `-NonInteractive`, `Read-Host "<Key> (<Used by>)"`; a typed path that does not exist prints a warning and is kept; write the file (template header lines verbatim, rows with the answers, Status `set by you` / `fill in`). Existing file without `-Force`: append only rows whose Key is absent (asked the same way), keep everything else byte-for-byte, print `kept N row(s), added M`. `-Force`: treat as no existing file (backup first). `-NonInteractive`: write the template as is. `-WhatIf`: print what would be asked/written, write nothing.
4. Summary and the Next lines (`machinecfg`, `prof help`, `ai\README.md`).

- [ ] **Step 1: Write the failing tests** (`InstallProfile.Tests.ps1`: fixture `ai\profile` tree under `New-TestRoot 'installprofile'` with one `PowerShell\x.ps1`, a `modules.txt` with only a `WindowsPowerShell` row, a template with rows `ReposRoot | | cdevops | fill in` and `MarkitdownVenv | %USERPROFILE%\.venvs\markitdown | markitdown | set by Test Owner`; each case runs `pwsh -NoProfile -File Install-Profile.ps1 -ProfileDir <tmp> -ConfigPath <tmp\cfg.md> -SkipModules ...`, answers piped on stdin: `'D:\repos' | pwsh ...`)

```powershell
Test-Case 'copies PowerShell\ into -ProfileDir and reports the count' { Assert-True (Test-Path "$pd\x.ps1"); Assert-Match $out '1 file\(s\) updated' }
Test-Case 'second run: 0 updated' { Assert-Match $out '0 file\(s\) updated' }
Test-Case 'asks for every blank key, keeps a set one, writes the config' { $cfg row '| ReposRoot | D:\repos | cdevops | set by you |'; MarkitdownVenv row verbatim }
Test-Case 'a typed folder that does not exist warns and is kept' { Assert-Match $out 'WARNING.*does not exist'; row holds the value }
Test-Case 'existing config: missing keys appended, present rows (blank or not) untouched, no duplicates' { pre-create cfg with a blank ReposRoot row and a foreign row 'Foo | bar'; Assert ReposRoot still blank, Foo kept, MarkitdownVenv appended once; Assert-Match $out 'kept 2 row\(s\), added 1' }
Test-Case '-Force replaces the config after a backup' { }
Test-Case '-NonInteractive writes the template as is' { ReposRoot row blank, Status fill in }
Test-Case '-WhatIf writes nothing' { no profile file, no cfg }
Test-Case 'never mentions WindowsPowerShell' { Assert-NoMatch $out 'WindowsPowerShell'; Assert-NoMatch (Get-Content Install-Profile.ps1 -Raw) 'SkipWindowsPowerShell' }
```

- [ ] **Step 2: Run, verify they fail**

Run: `pwsh -NoProfile -File setup\tests\InstallProfile.Tests.ps1`
Expected: FAIL (`-ProfileDir` not a parameter; 5.1 text present).

- [ ] **Step 3: Rewrite `pwsh/Install-Profile.ps1`** per Behaviour. Row regex: `^\s*\|\s*([A-Za-z][A-Za-z0-9]*)\s*\|([^|]*)\|([^|]*)\|([^|]*)\|`.

- [ ] **Step 4: Run, verify pass; run the hard-path gate**

Expected: `9 passed, 0 failed`; gate exit 0 (if the gate flags the `C:\Deploy\Setup\ProfileMachineConfig.md` default, add that line to `setup\hardpaths-allowlist.txt`: it is the convention path, not a personal one).

- [ ] **Step 5: Commit**

```bash
git add pwsh/Install-Profile.ps1 setup/tests/InstallProfile.Tests.ps1 setup/hardpaths-allowlist.txt
git commit -m "feat(prof): coworker Install-Profile: key prompts, missing-row merge, no 5.1 profile"
```

---

### Task 4: Skills offer, state and pick

**Files:**
- Create: `pwsh/PowerShell/Modules/Gene.Profile/ShareSkills.ps1` (header comment like Share.ps1: never shipped).
- Create: `setup/tests/ShareSkills.Tests.ps1` (dot-sources Target, Menu, Verbs, OtherGroup, Share, ShareSkills; fixture hub `skills\` with `testauto-a`, `testauto-b`, `testauto-c` (3 = category testauto), `crewchief-x`, `crewchief-y` (2 = general), `solo` (general), `odd-one` with front matter `category: tools`; each a `SKILL.md` `---\nname: <n>\ndescription: d\n---\nbody`; fixture repo = `git init` + one commit).

**Interfaces:**
- Consumes: Task 1 helpers.
- Produces:
  - `$script:SharePluginsRel = 'ai\plugins'`, `$script:ShareMarketplaceRel = '.claude-plugin\marketplace.json'`, `$script:ShareMarketplaceName = 'speed-merchants-dba'`.
  - `Get-GeneShareSkillCategory -Name <string> -Counts <hashtable firstToken=>count> -FrontMatter <hashtable>` returns string.
  - `Get-GeneShareSkillOffer [-Hub]` returns `[pscustomobject]{ Category; Skills = @([pscustomobject]{ Name; Path; Description }) }[]` sorted by category then name; reads every `skills\*\SKILL.md` front matter (`name:`, first `description:` line, `category:`).
  - `Get-GeneShareSkillState -Repo` returns ordered `category => @(skill names)` from `ai\plugins\<cat>\skills\*`.
  - `Read-GeneShareSkillPicks -Offer -State [-Reader]` returns ordered `category => @(names)` or `$null`; same keep/re-pick dialogue as `Read-GeneSharePicks`.

- [ ] **Step 1: Write the failing tests**

```powershell
Test-Case 'category: 3+ sharing the first token = that token; fewer = general; front matter wins' {
    Assert-Equal 'testauto' (Get-GeneShareSkillCategory -Name 'testauto-a' -Counts @{ testauto = 3 } -FrontMatter @{})
    Assert-Equal 'general'  (Get-GeneShareSkillCategory -Name 'crewchief-x' -Counts @{ crewchief = 2 } -FrontMatter @{})
    Assert-Equal 'general'  (Get-GeneShareSkillCategory -Name 'solo' -Counts @{ solo = 1 } -FrontMatter @{})
    Assert-Equal 'tools'    (Get-GeneShareSkillCategory -Name 'odd-one' -Counts @{ odd = 1 } -FrontMatter @{ category = 'tools' })
}
Test-Case 'offer: the fixture hub gives general (crewchief-x, crewchief-y, solo), testauto (a, b, c), tools (odd-one)' { }
Test-Case 'state: an empty repo holds nothing; plugins present say what is shared' { }
Test-Case 'pick: categories then skills by number; q cancels; Enter keeps what the repo has' { }
```

- [ ] **Step 2: Run, verify fail** (`Get-GeneShareSkillCategory` not recognized).
- [ ] **Step 3: Implement** the five functions in ShareSkills.ps1.
- [ ] **Step 4: Run, verify pass** (`4 passed`).
- [ ] **Step 5: Commit** `feat(prof): share skills: category, offer, state, pick`.

---

### Task 5: Skill checks and the reference rewrite

**Files:**
- Modify: `ShareSkills.ps1`, `ShareSkills.Tests.ps1`.

**Interfaces:**
- Produces:
  - `Get-GeneShareMachineKeys [-Hub]` returns the key names: `$global:GeneMachineDefaults` keys + `$global:GeneMachineAIKeys` read from the hub core by AST (no dot-sourcing), so `{Key}` detection uses the real list.
  - `Test-GeneShareSkillText -Text -Skill -AllSkills <string[]> -Picked <string[]> -Keys <string[]>` returns `@(string)` problems: `{Key}` tokens, and references to unpicked hub skills (`[[name]]`, `[[name|x]]`, `[[name#h]]`, `` `name` ``, `/name` with name in AllSkills and not in Picked). A name that is not a hub skill is never a problem.
  - `Convert-GeneShareSkillText -Text -Picked <string[]> -Category <hashtable name=>category> -AllSkills <string[]>` returns `[pscustomobject]{ Text; Rewrites; Unlinked }`: `[[p]]`/`[[p|x]]`/`[[p#h]]` => `<cat>:<p>`; `` `p` `` => `` `<cat>:<p>` ``; `/p` => `/<cat>:<p>`; `[[other]]` that is not a hub skill => `other` (Unlinked++). Self-references are rewritten too. Code fences are not exempt.
  - `Copy-GeneShareSkill -Source -Dest -Skill -Picked -Category -AllSkills -Keys` copies the folder: `.md` files through Test (throw on problems) then Convert; every other file byte-for-byte; returns `[pscustomobject]{ Files; Rewrites; Unlinked }`.

- [ ] **Step 1: Write the failing tests**

```powershell
Test-Case 'checks: {Key} token stops; a reference to an unpicked hub skill stops; a built-in /plugin or /loop never does' { Assert-Equal 2 @($r).Count }
Test-Case 'rewrite: [[p]], [[p|alias]], [[p#h]], `p` and /p become category:p; [[memory-note]] loses its brackets; counts reported' { }
Test-Case 'rewrite: /testauto-ab stays when only testauto-a is a skill (name boundary)' { }
Test-Case 'copy: SKILL.md rewritten, script.ps1 and a .png copied byte-for-byte' { write bytes 0x89 0x50 0x4E 0x47 0x0D 0x0A; compare hashes }
Test-Case 'keys: a fixture core with both tables yields ReposRoot and ShareRepo' { }
```

- [ ] **Step 2: Run, verify fail.**
- [ ] **Step 3: Implement.** Regexes: wiki `\[\[([^\]|#]+)(?:[|#][^\]]*)?\]\]`; backtick `` `([a-z0-9]+(?:-[a-z0-9]+)*)` ``; slash `(?<![\w/:])/([a-z0-9]+(?:-[a-z0-9]+)*)(?![\w-])`; key `\{(<keys joined by |>)\}`.
- [ ] **Step 4: Run, verify pass** (`9 passed`).
- [ ] **Step 5: Commit** `feat(prof): share skills: hard stops and reference rewrite`.

---

### Task 6: Plugin manifests, marketplace, the ai-setup flow

**Files:**
- Modify: `ShareSkills.ps1`, `ShareSkills.Tests.ps1`.

**Interfaces:**
- Consumes: Tasks 1, 4, 5.
- Produces:
  - `Get-GeneSharePluginHash -Dir` = SHA256 over `"<rel path>\n<file sha256>\n"` for every file under `skills\`, sorted, lowercase hex.
  - `New-GeneSharePluginManifest -Category -Skills <string[]> -Hash -Previous <hashtable or $null>` returns JSON text: `name` = category, `description` = `"<n> shared skill(s): a, b"`, `version` = `1.0.0` for a new plugin, the previous version when `Previous.metadata.contentHash -eq Hash`, else patch + 1; `metadata = @{ contentHash = Hash }`.
  - `New-GeneShareMarketplace -Owner -Plugins <ordered category=>skills>` returns JSON: `name` = `speed-merchants-dba`, `owner.name` = Owner, `description`, `plugins[]` = `{ name, source: "./ai/plugins/<cat>", description }` (no version in the entry).
  - `Write-GeneShareSkills -Plan [-WhatIf] [-Reader]`: stage under `Get-GeneShareStageRoot`\share-skills-<stamp>; copy picked skills via `Copy-GeneShareSkill`; `Test-GeneShareScans` over the stage; replace `ai\plugins` with the stage, write each plugin.json, `.claude-plugin\marketplace.json`, `ai\README.md` (`Get-GeneShareReadmeText`), root pointer; outside-change guard; `Show-GeneShareGitCommands` with message `share: skills <stamp>`. Returns `{ Repo; Files; Rewrites; Unlinked; Stamp; Written }`.
  - `Invoke-GeneShareAiSetup [-Repo] [-WhatIf] [-Reader]`: repo, assert, offer, state, picks (null = cancelled; empty = throw like profile), `Show-GeneShareSkillPlan`, write.

- [ ] **Step 1: Write the failing tests**

```powershell
Test-Case 'plugin.json: new = 1.0.0; same hash keeps the version; changed hash bumps the patch' { }
Test-Case 'marketplace.json: name speed-merchants-dba, owner, one entry per category with ./ai/plugins/<cat>; no plugins = []' { }
Test-Case 'flow: ai-setup -WhatIf stages, scans, lists files, writes nothing' { }
Test-Case 'write: ai\plugins\<cat>\skills\<skill>, plugin.json per category, marketplace.json at the root, README lists /plugin install <cat>@speed-merchants-dba; nothing else changed; git commands printed' { }
Test-Case 'write: unpicking every skill of a category removes the plugin folder and its marketplace entry' { }
Test-Case 'write: a second share is refused until the first is committed' { }
Test-Case 'scan: a {Key} token in a picked skill stops before anything is written' { }
Test-Case 'menu: Invoke-GeneProfShare -What ai-setup -WhatIf reaches the skills flow' { }
```

- [ ] **Step 2: Run, verify fail.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run, verify pass** (`17 passed`); Share.Tests (31) and Prof.Tests (85) too. If `claude` is on PATH: `claude plugin validate <fixture repo>` and `claude plugin validate <fixture repo>\ai\plugins\testauto`, both exit 0 (`Validation passed`); ledger the output. Ledger a note when the CLI is absent.
- [ ] **Step 5: Commit** `feat(prof): share ai-setup: plugin manifests, marketplace, write flow`.

---

### Task 7: Retire Promote-ToWork, docs, vault notes

**Files:**
- Delete: `tools/Promote-ToWork.ps1`.
- Modify: `share.yaml` (drop `skills:` and `agents:`; header comment: blockedPatterns feed `prof setup share`).
- Modify: `README.md` lines 13, 40-41; `skills/ai-repo-management/SKILL.md` lines 29, 58; `docs/manageprofile-design.md` line 128 note: all point at `prof setup share` (share repo, `ai\`, marketplace, never commits).
- Modify: `Share.ps1` `Show-GeneShareHelp`: add the resolved repo path line when `Get-GeneShareRepo` resolves (else the row name).
- Vault (via `C:\Users\agenewe\.claude\bin\Write-AIFile.ps1 -Path -Source`): `Q:\Work\Work\99_Frequent\Profile\Coworker Handoff.md` rewritten from spec 5.5 (coworker: clone, Install-Profile -WhatIf, Install-Profile, /plugin marketplace add, /plugin install, update; Gene: `prof setup share profile|ai-setup`, run the printed git commands); `Share Design.md` status line `BUILT 2026-10-23 (work/prof-share)`; `Profile Guide.md` 1.1 table: export row becomes share.

- [ ] **Step 1: Failing check**: `grep -rn "Promote-ToWork\|setup export\|^skills:\|^agents:" README.md skills/ai-repo-management/SKILL.md docs/manageprofile-design.md share.yaml tools` returns hits now.
- [ ] **Step 2: Apply the edits and deletes.**
- [ ] **Step 3: Verify**: the same grep returns nothing; Share.Tests still `31 passed` (share.yaml parses); gate exit 0; `cat` the vault notes back and compare the hash Write-AIFile printed.
- [ ] **Step 4: Commit** `chore(prof): retire Promote-ToWork and export; docs point at prof setup share`.

---

### Task 8: Verify against the real share repo

No commits in the dba clone. Everything here is `-WhatIf` or read-only unless Gene says otherwise at the time.

- [ ] **Step 1:** In a child pwsh importing the module from the repo: `Invoke-GeneShareProfile -WhatIf -Reader <queue>` picking navigate + tabs against the real clone. Expected: plan printed, `(nothing written)`, `git -C C:\devops\repos\speed-merchants-dba status --porcelain` empty.
- [ ] **Step 2:** `Invoke-GeneShareAiSetup -WhatIf` with one testauto skill that has no `{Key}` (`testauto-log-tags`). Expected: staged, rewrite counts printed, nothing written.
- [ ] **Step 3:** Full suite: every `setup\tests\*.Tests.ps1` + `Test-NoHardPaths.ps1`; counts in the ledger.
- [ ] **Step 4 (ask Gene first: touches his Claude config):** after a real `ai-setup` share is written (not committed): `claude plugin marketplace add C:\devops\repos\speed-merchants-dba`, then `claude plugin marketplace list` shows it, then `claude plugin marketplace remove speed-merchants-dba`. Try the ADO URL form the same way; the README keeps the form that worked (clone path today; URL only if it passed).
- [ ] **Step 5:** Final fresh review of the branch, fix pass, `merge --no-ff` on the laptop, ledger summary for Gene.
