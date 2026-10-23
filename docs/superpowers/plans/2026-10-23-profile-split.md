# Profile Split Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split the one-file PowerShell 7 profile into a core file plus one `profile.d\<category>.ps1` per `prof other` catalog category, and split the `prof` hub so the machine-moving setup verbs live in their own file, with no behaviour change, so that change 2 (`prof setup share`) can ship picked categories by copying files.

**Architecture:** `Microsoft.PowerShell_profile.ps1` keeps everything that runs at load (machine config, PSReadLine, prompt, module re-import) and every helper two or more categories use, then dot-sources every `profile.d\*.ps1` in name order. Each category file holds only definitions (functions, aliases, variable assignments), never a call, so load order cannot matter. In `Gene.Profile`, `Verbs.ps1` keeps the dispatcher, help and menu; `SetupGroup.ps1` registers the setup group like `BuildGroup.ps1` registers build; the module loads whatever group files exist; help, menu and the `prof other` catalog list only commands whose function is defined. A census test proves the set of functions, aliases and globals is unchanged.

**Tech Stack:** PowerShell 7.2+, `System.Management.Automation.Language` AST, the repo's own test harness (`setup\tests\TestHarness.ps1`, no Pester), git.

**Spec:** `Q:\Work\Work\99_Frequent\Profile\Share Design.md` (vault), sections 2, 3, 4.

## Global Constraints

- Repo: `C:\devops\repos\ai-setup`, branch `work/profile-split` off `main`; both clones clean before starting (GIT FLOW rule). Commits allowed on this repo; Gene pushes.
- Zero behaviour change: every function and alias keeps its name, scope (global, as today) and body. No renames, no module conversion.
- Category file names = `prof other` catalog keys exactly: `navigate`, `tabs`, `build`, `git`, `board`, `profile`, `claude`, `tools`.
- A `profile.d` file contains only top-level definitions: `function`, `Set-Alias` / `Remove-Alias` / `New-Alias`, variable assignments. Any other top-level statement belongs in core.
- A helper used by two or more categories lives in core. A helper used by one category lives in that category's file.
- `pwsh\*` is allowlisted in `setup\hardpaths-allowlist.txt`; nothing to add for the gate.
- Tests run with `pwsh -NoProfile -File <test>`; `Complete-Tests` exits 1 on failure. Every existing test in `setup\tests\` stays green.
- `install.ps1` step 4, `Install-Profile.ps1` and `Invoke-GeneProfExport` already copy `pwsh\PowerShell` recursively: `profile.d` needs no installer change.
- Gene runs `prof setup reload` and the SMVMTR1 push; the plan never does.

## Review Focus

1. A category file that calls a helper defined in another category file loads fine on the laptop (everything is loaded) and breaks in a trimmed copy. Test: cross-reference check in Task 1, run against every file.
2. `Get-GeneWtPath` / `Test-GeneWt` are used by `tabs` (New-GeneTab) and `board`; `New-GeneWtTab` reads `$global:GeneStreamTabColors` (board). A wrong home for any of them breaks `addtab` when board is not shipped. Test: the cross-reference check plus the "tabs only" load test in Task 4.
3. `$script:` variables (`GeneAiPaths`, `GeneModulesLoaded`, `ClaudeAccountDirs`, `DotnetSuggestLoaded`) resolve in the profile's script scope because `profile.d` files are dot-sourced, not run. A future `& file` instead of `. file` would silently break them. Test: Task 2 load test asserts `Get-GeneAiGitPaths` returns six entries after a fresh load.
4. `Gene.Profile` with `SetupGroup.ps1`, `Target.ps1`, `Sync.ps1` removed must import without error and `prof help` must not mention setup. Test: Task 6 trimmed-module test.
5. `prof setup show` compares only the profile file and `Modules\`; after the split an edited `profile.d` file would read "in sync". Test: Task 7.

---

### Task 1: Census and structure tests (red)

**Files:**
- Create: `setup\tests\ProfileAst.ps1` (the two AST helpers; dot-sourced by the test and by child pwsh processes)
- Create: `setup\tests\ProfileSplit.Tests.ps1`
- Create: `setup\tests\fixtures\profile-names.baseline.txt`

**Interfaces:**
- Produces (in `ProfileAst.ps1`): `Get-GeneProfileCalls -Ast <Ast>` : `[string[]]` of every `CommandAst` command name under that AST. `Get-GeneProfileDefinitions -Path <file>`: returns `[pscustomobject]@{ Functions = [string[]]; Aliases = [string[]]; Globals = [string[]]; Calls = [string[]]; OtherTopLevel = [string[]] }` from the AST. `Functions` = every `FunctionDefinitionAst` name (nested included). `Aliases` = `-Name` of every `Set-Alias`/`New-Alias` `CommandAst`. `Globals` = every `$global:X` assigned at any depth. `Calls` = every `CommandAst` command name (first element) anywhere. `OtherTopLevel` = text of top-level statements that are not a function definition, assignment, or `Set-Alias`/`Remove-Alias`/`New-Alias` call.
- Produces: `Get-ProfileFiles` = `pwsh\PowerShell\Microsoft.PowerShell_profile.ps1` plus `pwsh\PowerShell\profile.d\*.ps1` sorted by name.

- [ ] **Step 1: Write the baseline from the unsplit profile**

Run from the repo root on `main` before any edit:

```powershell
pwsh -NoProfile -Command ". .\setup\tests\ProfileSplit.Tests.ps1 -WriteBaseline"
```

The test file takes `-WriteBaseline`: it runs `Get-GeneProfileDefinitions` on the single profile file and writes `Functions`, `Aliases`, `Globals` sorted and unique, one per line prefixed `function `, `alias `, `global `, to `setup\tests\fixtures\profile-names.baseline.txt`, then exits 0 without running cases. Commit that file; it never changes again in this change.

- [ ] **Step 2: Write the test cases**

```powershell
Test-Case 'census: the split defines exactly the names the one-file profile defined' {
    $now = @(Get-ProfileFiles | ForEach-Object { Get-GeneProfileDefinitions -Path $_ })
    $names = @($now.Functions | ForEach-Object { "function $_" }) + @($now.Aliases | ForEach-Object { "alias $_" }) + @($now.Globals | ForEach-Object { "global $_" }) | Sort-Object -Unique
    Assert-Equal (Get-Content $baseline | Sort-Object -Unique) $names
}
Test-Case 'structure: profile.d files hold only definitions' {
    foreach ($f in Get-ChildItem "$pwshDir\profile.d\*.ps1") { Assert-Equal @() (Get-GeneProfileDefinitions -Path $f.FullName).OtherTopLevel "in $($f.Name)" }
}
Test-Case 'structure: no profile.d file calls a function another profile.d file defines' {
    $owner = @{}
    foreach ($f in Get-ChildItem "$pwshDir\profile.d\*.ps1") { foreach ($n in (Get-GeneProfileDefinitions -Path $f.FullName).Functions) { $owner[$n] = $f.Name } }
    $bad = foreach ($f in Get-ChildItem "$pwshDir\profile.d\*.ps1") {
        foreach ($c in (Get-GeneProfileDefinitions -Path $f.FullName).Calls | Sort-Object -Unique) { if ($owner.ContainsKey($c) -and $owner[$c] -ne $f.Name) { "$($f.Name) calls $c (defined in $($owner[$c]))" } }
    }
    Assert-Equal @() @($bad)
}
Test-Case 'structure: core dot-sources profile.d in name order' {
    Assert-Match (Get-Content $core -Raw) 'Get-ChildItem[^\r\n]*profile\.d[^\r\n]*\.ps1[^\r\n]*Sort-Object[^\r\n]*Name'
}
Test-Case 'load: a fresh pwsh loads the split profile and defines every baseline function' {
    $names = pwsh -NoProfile -Command ". '$core'; (Get-Command -CommandType Function).Name; 'ALIAS:' + ((Get-Alias).Name -join ',')"
    foreach ($b in Get-Content $baseline | Where-Object { $_ -like 'function *' }) { Assert-True ($names -contains $b.Substring(9)) "$b missing after load" }
    Assert-True (($names | Where-Object { $_ -like 'ALIAS:*' }) -match '(^|,)machinecfg(,|$)') 'machinecfg alias missing'
}
Test-Case 'load: script-scope state survives dot-sourcing (Get-GeneAiGitPaths)' {
    Assert-Equal '6' (pwsh -NoProfile -Command ". '$core'; (Get-GeneAiGitPaths).Count")
}
```

- [ ] **Step 3: Run; expect the structure and load cases to FAIL (no `profile.d` yet, no loader line), census to PASS**

```powershell
pwsh -NoProfile -File .\setup\tests\ProfileSplit.Tests.ps1
```

- [ ] **Step 4: Commit**

```powershell
git -C C:\devops\repos\ai-setup add setup\tests\ProfileSplit.Tests.ps1 setup\tests\fixtures\profile-names.baseline.txt
git -C C:\devops\repos\ai-setup commit -m "profile split: census baseline and structure tests (red)"
```

---

### Task 2: Core loader plus the small categories (navigate, profile, claude, tools)

**Files:**
- Modify: `pwsh\PowerShell\Microsoft.PowerShell_profile.ps1`
- Create: `pwsh\PowerShell\profile.d\navigate.ps1`, `profile.ps1`, `claude.ps1`, `tools.ps1`

**Interfaces:**
- Produces: core ends its definitions section with the loader, placed just before the trailing `Gene.*` re-import loop:

```powershell
# Categories: one file per prof other category (navigate, tabs, build, git, board, profile, claude, tools). Each holds only
# definitions, so the order is for reading, not for correctness. prof setup share copies the picked files.
foreach ($geneCategoryFile in Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'profile.d') -Filter '*.ps1' -ErrorAction SilentlyContinue | Sort-Object Name) { . $geneCategoryFile.FullName }
Remove-Variable -Name geneCategoryFile -ErrorAction SilentlyContinue
```

- [ ] **Step 1: Move the functions, text unchanged, into their files**

| File | Moves there |
|---|---|
| `navigate.ps1` | `cdevops`, `caiprof`, `cspeed`, `ccrew`, `csm`, `cpower`, `csql`, `ccursor` |
| `profile.ps1` | `sp`, `ep`, the `Remove-Alias -Name rp` line and `rp` |
| `claude.ps1` | the whole `#region Claude account profiles` (its `$script:ClaudeAccountDirs`, `Start-ClaudeAccount`, `claude-work`, `claude-home`, `Get-ClaudeAccount`, `Set-Alias claude-which`) |
| `tools.ps1` | `chocoenv`, `cleannul`, `newguid`, `markitdown` and its three `$global:markitdown*` assignments |

Stays in core: the `dotnet-suggest` block (`if (Get-Command "dotnet-suggest")` with its nested functions): it is a conditional statement, not a definition, and it is completion plumbing, not a command.

- [ ] **Step 2: Add the loader to core (Interfaces block) and run the tests**

```powershell
pwsh -NoProfile -File .\setup\tests\ProfileSplit.Tests.ps1
```

Expected: all PASS. If "no profile.d file calls a function another profile.d file defines" fails, move the named helper into core and rerun. If the fresh-load case fails inside the PSReadLine lines of core, that is pre-existing behaviour of a non-interactive child: report it, do not edit core to hide it.

- [ ] **Step 3: Run the existing suites that load the profile pieces**

```powershell
pwsh -NoProfile -File .\setup\tests\Prof.Tests.ps1
```

Expected: same pass count as on `main`.

- [ ] **Step 4: Commit**

```powershell
git -C C:\devops\repos\ai-setup add pwsh\PowerShell
git -C C:\devops\repos\ai-setup commit -m "profile split: core loader; navigate, profile, claude, tools categories"
```

---

### Task 3: git and build categories

**Files:**
- Modify: `pwsh\PowerShell\Microsoft.PowerShell_profile.ps1`
- Create: `pwsh\PowerShell\profile.d\git.ps1`, `build.ps1`

- [ ] **Step 1: Move**

| File | Moves there |
|---|---|
| `git.ps1` | `$script:GeneAiPaths`, `Get-GeneAiGitPaths`, `pushrules`, `dpAI`, `pps`, `psql`, `gpush` |
| `build.ps1` | `Publish-GeneSharedBits`, `Publish-SpeedMerchantsPackage`, `dpspeed`, `dpcrewchief`, `dpdatagen`, `dpmutate`, `dpall`, `dpv2`, `dpContainers` |

Stays in core: `$script:GeneModulesLoaded`, `$global:GeneBitsDir`, `Import-GeneModuleOnce` (build and the dotnet block use them).

- [ ] **Step 2: Run the split tests and Prof.Tests; expect PASS; fix cross-reference failures by moving the helper to core**

- [ ] **Step 3: Commit**

```powershell
git -C C:\devops\repos\ai-setup add pwsh\PowerShell
git -C C:\devops\repos\ai-setup commit -m "profile split: git and build categories"
```

---

### Task 4: tabs and board categories

**Files:**
- Modify: `pwsh\PowerShell\Microsoft.PowerShell_profile.ps1`
- Create: `pwsh\PowerShell\profile.d\tabs.ps1`, `board.ps1`
- Modify: `setup\tests\ProfileSplit.Tests.ps1` (one more case)

- [ ] **Step 1: Add the "tabs without board" load test first**

```powershell
Test-Case 'load: core + tabs alone defines addtab and New-GeneTab resolves every command it calls' {
    $tmp = New-TestRoot 'split'; Copy-Item $core $tmp; New-Item "$tmp\profile.d" -ItemType Directory | Out-Null; Copy-Item "$pwshDir\profile.d\tabs.ps1" "$tmp\profile.d"
    $missing = pwsh -NoProfile -Command ". '$tmp\Microsoft.PowerShell_profile.ps1'; (Get-GeneProfileCalls (Get-Command New-GeneTab).ScriptBlock.Ast + (Get-Command addtab).ScriptBlock.Ast) | Where-Object { -not (Get-Command `$_ -ErrorAction SilentlyContinue) }"
    Assert-Equal @() @($missing)
}
```

(The child pwsh dot-sources `setup\tests\ProfileAst.ps1` first to get `Get-GeneProfileCalls`.)

- [ ] **Step 2: Run; expect FAIL (tabs.ps1 does not exist)**

- [ ] **Step 3: Move**

| File | Moves there |
|---|---|
| `tabs.ps1` | `addtab`, `addnew`, `Set-Alias ntab`, `addLinux` |
| `board.ps1` | the whole `#region Stream sessions` content: its `$global:GeneStream*` assignments and every function from `Get-GeneStreamKitPath` to `updateStreams` |

Stays in core (used by both): `$global:GeneTabColorRules`, `$global:GeneTabDefaultColor`, `Get-GeneTabColor`, `New-GeneTab`, `Get-GeneWtPath`, `Test-GeneWt`. `New-GeneWtTab` goes to `board.ps1` (only board calls it).

- [ ] **Step 4: Run the split tests and Prof.Tests; expect PASS**

- [ ] **Step 5: Commit**

```powershell
git -C C:\devops\repos\ai-setup add pwsh\PowerShell setup\tests
git -C C:\devops\repos\ai-setup commit -m "profile split: tabs and board categories; core keeps the shared tab helpers"
```

---

### Task 5: Hub split: SetupGroup.ps1 and a file-agnostic module loader

**Files:**
- Modify: `pwsh\PowerShell\Modules\Gene.Profile\Verbs.ps1`
- Create: `pwsh\PowerShell\Modules\Gene.Profile\SetupGroup.ps1`
- Modify: `pwsh\PowerShell\Modules\Gene.Profile\Gene.Profile.psm1`
- Modify: `setup\tests\Prof.Tests.ps1:262` (add `SetupGroup.ps1` to the dot-source list, after `Verbs.ps1`)

**Interfaces:**
- Produces: `Verbs.ps1` defines `$script:ProfGroups = [ordered]@{}` (empty), `$script:ProfOldNames`, `Write-ProfStep/Warn/Note`, `Format-GeneProfCommand`, `Confirm-GeneProf`, `Resolve-GeneProfCommand`, `Show-GeneProfHelp`, `Invoke-GeneProfMenu`, `Invoke-GeneProf`, the two aliases.
- Produces: `SetupGroup.ps1` defines `$script:ProfVerbs`, `$script:ProfDetails`, `$script:ProfUsage`, registers `$script:ProfGroups['setup']` exactly as `Verbs.ps1` does today, and holds `Get-GeneHubProfile`, `Get-GeneHubRepo`, `Invoke-GeneLocalInstall`, `Get-GeneTargetClone`, `Assert-GenePerUser`, `Get-GeneRemoteRepoStates`, `Get-GeneRuntimeRevision`, every `Invoke-GeneProf<Verb>` for the twelve setup verbs, their helpers (`Get-GeneProfileFix` … `Invoke-GeneSecretsOn`), and `Read-GeneSetupMenuParams`.
- Produces: `Gene.Profile.psm1` loader:

```powershell
foreach ($f in 'Target.ps1', 'Sync.ps1', 'Menu.ps1', 'Verbs.ps1') { $p = Join-Path $PSScriptRoot $f; if (Test-Path -LiteralPath $p) { . $p } }
foreach ($f in Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1' | Where-Object { $_.Name -notin 'Target.ps1', 'Sync.ps1', 'Menu.ps1', 'Verbs.ps1' } | Sort-Object Name) { . $f.FullName }
$exports = @('Invoke-GeneProf', 'Select-GeneMenu', 'Read-GeneYesNo', 'Read-GeneText', 'Get-GeneMachines', 'Add-GeneMachine', 'Get-GeneHubRoot', 'Resolve-GeneTarget', 'Close-GeneTarget') | Where-Object { Get-Command $_ -CommandType Function -ErrorAction SilentlyContinue }
Export-ModuleMember -Function $exports -Alias prof, manageProfile
```

and `Gene.Profile.psd1` `FunctionsToExport = '*'` (the psm1 decides).

- [ ] **Step 1: Write the failing test in `Prof.Tests.ps1`**

```powershell
Test-Case 'hub: setup group is registered by SetupGroup.ps1, not Verbs.ps1' {
    Assert-NoMatch (Get-Content "$mod\Verbs.ps1" -Raw) "ProfGroups\['setup'\]|ProfGroups = \[ordered\]@\{\s*setup"
    Assert-Match (Get-Content "$mod\SetupGroup.ps1" -Raw) "ProfGroups\['setup'\]"
}
```

- [ ] **Step 2: Run `Prof.Tests.ps1`; expect that case to FAIL**

- [ ] **Step 3: Move the code (Interfaces block), update the psm1 and psd1, update the test's dot-source list**

- [ ] **Step 4: Run `Prof.Tests.ps1`; expect all PASS, count = previous + 1**

- [ ] **Step 5: Commit**

```powershell
git -C C:\devops\repos\ai-setup add pwsh\PowerShell\Modules\Gene.Profile setup\tests\Prof.Tests.ps1
git -C C:\devops\repos\ai-setup commit -m "prof: setup verbs move to SetupGroup.ps1; module loads the group files that exist"
```

---

### Task 6: Hub self-filter: list only what is defined

**Files:**
- Modify: `pwsh\PowerShell\Modules\Gene.Profile\Verbs.ps1`
- Modify: `pwsh\PowerShell\Modules\Gene.Profile\OtherGroup.ps1`
- Modify: `setup\tests\Prof.Tests.ps1`

**Interfaces:**
- Produces in `Verbs.ps1`:
  - `Get-GeneProfGroupNames` : `[string[]]` of `$script:ProfGroups` keys whose group has at least one verb `v` with `Get-Command ($g.Prefix + TitleCase(v))` defined, or whose group has a `Menu`/`TopicNames` (the `other` group's verbs are catalog keys, not functions; it counts as present when `Get-GeneOtherCategories` returns anything). Every place that enumerates `$script:ProfGroups.Keys` (`Resolve-GeneProfCommand`, `Show-GeneProfHelp`, `Invoke-GeneProfMenu`, both `ArgumentCompleter`s) uses it.
  - `$script:ProfOldNames` becomes `[object[]]` of `[pscustomobject]@{ Old; New; Needs }` where `Needs` is one function name (`sp`→`sp`, `ep`→`ep`, `rp`→`rp`, `machinecfg`→`Show-GeneMachineConfig`, `gpush`→`gpush`, the dp* rows→`dpspeed`, `dpall -Package`→`dpall`); help prints a row only when `Get-Command $_.Needs` is defined.
  - `Show-GeneProfHelp` prints the machines footer line only when `Get-Command Get-GeneMachinesPath` is defined; the `-Machine` completer returns `@()` when `Get-GeneMachines` is not defined.
- Produces in `OtherGroup.ps1`:
  - `Get-GeneOtherEntries -Category <key>` : the catalog entries of that category whose `Name` resolves with `Get-Command -ErrorAction SilentlyContinue` (function or alias).
  - `Get-GeneOtherCategories` : catalog keys with at least one such entry. `Show-GeneOtherCategory`, `Read-GeneOtherMenu`, the `TopicNames` block and the `Verbs`/`Details` registration loop use these two.

- [ ] **Step 1: Write the failing tests (in the block that dot-sources the hub files)**

```powershell
Test-Case 'filter: prof other hides a command whose function is not defined' {
    function global:zzprobe { }
    $script:ProfOtherCatalog['tools'].Commands += New-GeneOtherEntry 'zzprobe' 'probe' @('zzprobe')
    Assert-True ((Get-GeneOtherEntries -Category tools).Name -contains 'zzprobe')
    Remove-Item function:\zzprobe
    Assert-True ((Get-GeneOtherEntries -Category tools).Name -notcontains 'zzprobe')
}
Test-Case 'filter: a group with no defined verb function is not listed' {
    $script:ProfGroups['zz'] = [pscustomobject]@{ Description = 'x'; Verbs = [ordered]@{ go = 'go' }; Details = @{}; Usage = @{}; Prefix = 'Invoke-GeneProfZz'; NeedMachine = @() }
    Assert-True ((Get-GeneProfGroupNames) -notcontains 'zz')
    function global:Invoke-GeneProfZzGo { }
    Assert-True ((Get-GeneProfGroupNames) -contains 'zz')
    Remove-Item function:\Invoke-GeneProfZzGo; $script:ProfGroups.Remove('zz')
}
Test-Case 'filter: old-name rows need their function' {
    Assert-True (@($script:ProfOldNames | Where-Object { $_.Old -eq 'gpush' }).Needs -eq 'gpush')
}
Test-Case 'trimmed hub: without SetupGroup/Target/Sync/Export the module imports and prof help has no setup group' {
    $t = New-TestRoot 'hub'; Copy-Item "$mod\*" $t -Recurse
    Remove-Item "$t\SetupGroup.ps1", "$t\Target.ps1", "$t\Sync.ps1", "$t\Export.ps1"
    $o = pwsh -NoProfile -Command "`$ErrorActionPreference='Stop'; Import-Module '$t\Gene.Profile.psd1' -DisableNameChecking; prof help 6>&1 | Out-String; 'EXIT-OK'"
    Assert-Match ($o -join "`n") 'EXIT-OK'
    Assert-NoMatch ($o -join "`n") '(?m)^setup  '
    Assert-Match ($o -join "`n") '(?m)^other  '
}
```

- [ ] **Step 2: Run; expect the four cases to FAIL**

- [ ] **Step 3: Implement the Interfaces block**

- [ ] **Step 4: Run `Prof.Tests.ps1`; expect all PASS. Also run `prof help` and `prof other` interactively once and eyeball that nothing disappeared on the laptop (everything is defined there).**

- [ ] **Step 5: Commit**

```powershell
git -C C:\devops\repos\ai-setup add pwsh\PowerShell\Modules\Gene.Profile setup\tests\Prof.Tests.ps1
git -C C:\devops\repos\ai-setup commit -m "prof: help, menu and catalog list only commands that are defined"
```

---

### Task 7: `prof setup show` compares the whole profile tree

**Files:**
- Modify: `pwsh\PowerShell\Modules\Gene.Profile\SetupGroup.ps1` (`Invoke-GeneProfShow`)
- Modify: `setup\tests\Prof.Tests.ps1`

**Interfaces:**
- Produces: `Compare-GeneProfileTrees -Repo <dir> -Installed <dir>` : `[pscustomobject]@{ Profile = 'in sync'|'differs'|'missing'; Categories = <int differing or missing profile.d files>; Modules = <int differing or missing module files> }`, comparing by `Get-FileHash`; `Invoke-GeneProfShow` calls it with `<hub>\pwsh\PowerShell` and `Split-Path $PROFILE` and prints the three lines (today's two plus `Categories: n file(s) differ`).

- [ ] **Step 1: Write the failing test**

```powershell
Test-Case 'show: a changed profile.d file counts as a difference' {
    $r = New-TestRoot 'show'; $i = New-TestRoot 'inst'
    foreach ($d in $r, $i) { New-Item "$d\profile.d", "$d\Modules\M" -ItemType Directory -Force | Out-Null; Set-Content "$d\Microsoft.PowerShell_profile.ps1" 'a'; Set-Content "$d\profile.d\git.ps1" 'b'; Set-Content "$d\Modules\M\M.psm1" 'c' }
    Assert-Equal 0 (Compare-GeneProfileTrees -Repo $r -Installed $i).Categories
    Set-Content "$i\profile.d\git.ps1" 'changed'
    Assert-Equal 1 (Compare-GeneProfileTrees -Repo $r -Installed $i).Categories
    Assert-Equal 'in sync' (Compare-GeneProfileTrees -Repo $r -Installed $i).Profile
}
```

- [ ] **Step 2: Run; expect FAIL (function not defined)**
- [ ] **Step 3: Implement; `Invoke-GeneProfShow` uses it**
- [ ] **Step 4: Run; expect PASS**
- [ ] **Step 5: Commit**

```powershell
git -C C:\devops\repos\ai-setup add pwsh\PowerShell\Modules\Gene.Profile\SetupGroup.ps1 setup\tests\Prof.Tests.ps1
git -C C:\devops\repos\ai-setup commit -m "prof setup show: compares profile.d too"
```

---

### Task 8: Docs and the full gate

**Files:**
- Modify: `docs\manageprofile-design.md` (section near line 73: a group is registered by its own file; setup by `SetupGroup.ps1`)
- Modify (vault, via `C:\Users\agenewe\.claude\bin\Write-AIFile.ps1 -Path -Source`): `Q:\Work\Work\99_Frequent\Profile\Profile Guide.md` row at line 31: the profile is a core file plus `profile.d\<category>.ps1`, one per `prof other` category; list the eight.
- Modify: `C:\Users\agenewe\.claude\memory\project_prof_share_design_2026-10-23.md`: status line "change 1 built, awaiting reload".

- [ ] **Step 1: Edit the three documents**
- [ ] **Step 2: Run every test and the gate**

```powershell
Get-ChildItem .\setup\tests\*.Tests.ps1 | ForEach-Object { pwsh -NoProfile -File $_.FullName; if ($LASTEXITCODE) { "FAILED: $($_.Name)" } }
```

```powershell
pwsh -NoProfile -File .\setup\Test-NoHardPaths.ps1 -Summary
```

Expected: no `FAILED:` line; gate exit 0.

- [ ] **Step 3: Commit, merge on this machine, hand to Gene**

```powershell
git -C C:\devops\repos\ai-setup add -A
git -C C:\devops\repos\ai-setup commit -m "profile split: docs"
git -C C:\devops\repos\ai-setup checkout main
git -C C:\devops\repos\ai-setup merge --no-ff work/profile-split -m "Merge branch 'work/profile-split'"
```

Then tell Gene: run `prof setup reload`, open a new tab, type `prof help`, `prof other`, `addtab x`, `cspeed`; push to SMVMTR1 with `prof setup push -Machine SMVMTR1 -AllowSecrets` when the board is quiet.
