---
name: inno-setup-installer
description: >
  The FOUR sibling Windows install packages built from this repo — CrewChief, TestAuto,
  TestDataGeneration and DataGenerationAndMutation — one self-contained Inno Setup Setup.exe each, built
  by New-*Installer.ps1, with deliberately inverted appsettings/upgrade rules and deliberately disjoint
  web ports. Use when building, version-bumping, or shipping any of the four installers, editing
  CrewChief.iss / TestAuto.iss / TestDataGeneration.iss / DataGenerationAndMutation.iss or their build
  scripts, the ISCC7→6 compiler fallback, the per-tool version-bump source, install modes (Windows
  Service vs shortcuts), the operator-chosen web port and which file each installer writes it to, the
  never-change AppId rule, or why operator state is never listed in [Files].
---
# Inno Setup Installer (four sibling packages)

Two Windows install packages, built the same way, with deliberately **inverted** rules. Each ships as ONE self-contained `*-Setup-<version>.exe` (a full win-x64 publish embedded — the target box needs no .NET runtime). This skill spans BOTH repos' installers; it is a build/tooling skill.

| | **CrewChief** | **TestAuto** |
| --- | --- | --- |
| Build script | `CrewChief/installer/New-CrewChiefInstaller.ps1` | `installer/New-TestAutoInstaller.ps1` (repo root) |
| .iss | `CrewChief/installer/CrewChief.iss` | `installer/TestAuto.iss` |
| Wrapper | `dpcrewchief -Package [-Bump\|-BumpMinor\|-BumpMajor]` | `dpspeed -Package [-Bump\|-BumpMinor\|-BumpMajor]` |
| Version source | `Directory.Build.props` `<Version>` (`CrewChief/Directory.Build.props:14` — **re-read the file, never quote the number**) | `TestAuto.Web.csproj` `<Version>` (`:18`) — **re-read it too** |
| Version scheme | Major.Minor.Patch | Major.Minor.Patch (**same as CrewChief since 2026-08-12**) |
| Install mode | Windows Service (default) **or** shortcuts-only | Windows Service (default task) **or** shortcuts-only (as of 2026-08-08) |
| Service account | **No LocalSystem** — `sicKeepCurrent` (only when a real non-built-in account is already in place) or `sicSpecific`; page shown whenever the `service` task is selected, incl. upgrades; `PrepareToInstall` refuses if `sicSpecific` resolves no account | **Named DOMAIN account required** — no LocalSystem, **local machine accounts hard-refused**; must be local admin on the box (direct-membership check WARNS, nested groups invisible); non-`a*` name warns; field pre-fills `{userdomain}\{username}` |
| appsettings on upgrade | `appsettings.json` **ships fresh every upgrade** (new keys arrive); machine-local values go in `appsettings.Production.json` (created empty once, never overwritten) | **Ships fresh every upgrade too** (flipped 2026-08-09 — machine values live in the SECRETS profile, not appsettings). Environment overlays (Development/Production/CommandLine) are dev-box files: stripped from stage AND deleted from installed boxes via `[InstallDelete]` (a stale Production overlay loads under service mode and once shipped a dev hostname + certless Kestrel HTTPS endpoint) |
| Secrets | Files-only. Service mode: `%ProgramData%\CrewChief\secrets` (machine-shared, ACL Administrators+SYSTEM), advertised via machine env var `CREWCHIEF_SECRETS_FOLDER` | Profisee DB (`TestAutoSecrets`) via in-app `/secrets/bootstrap` (redirect middleware live). Installer creates machine store `%ProgramData%\TestAuto` (no `\secrets` subfolder; holds master.json + dataprotection-keys), ACL Admins+SYSTEM+account, env var `TESTAUTO_SECRETS_FOLDER` — see `MasterConfigPathResolver` |
| `ChangesEnvironment` | `yes` (broadcasts WM_SETTINGCHANGE for CREWCHIEF_SECRETS_FOLDER/PATH) | `yes` (TESTAUTO_SECRETS_FOLDER; as of 2026-08-08) |
| Update feed | — | App watches `Updates:FeedFolder` (default = the team share) for a newer `TestAuto-Setup-*.exe`; banner + one-click `/VERYSILENT` self-update in service mode (`UpdateCheckService`) |
| Ports (firewall task) | 5030/5031 | 8080/8443 | *(TestDataGeneration 5045/5046, DataGenerationAndMutation 5047/5048 - see the four-product section below. 5040 is deliberately avoided because CDPSvc/svchost already binds it.)* |

Memory: `project_crewchief_installer_plan`. The design rationale lives in `Plan_CrewChiefInstaller.md` (Work vault); TestAuto's rules are §8 of that plan.

## The build pipeline (both scripts, 5 stages)

Both `New-*Installer.ps1` are **profile-free** — anyone with the repo can run them; the `dp*` wrappers are just convenience. Both `#Requires -Version 7`, default `-Configuration Release`, default `-OutputDir {ScratchRoot}`, and support `-SkipInstallerCompile` (publish + stage only).

1. **Preflight** — require `dotnet` on PATH; require the project/props/.iss files exist. Locate `ISCC.exe` by preferring **Inno Setup 7** (x64-native setup binaries) and falling back to **6.x** (`Get-Command iscc.exe`, then `Program Files`/`Program Files (x86)`/`LOCALAPPDATA` for 7 then 6). Missing ⇒ throw with an install hint.
2. **Read version** — both parse a hand-maintained 3-part `<Version>` (CrewChief from
   `Directory.Build.props`, TestAuto from `TestAuto.Web.csproj`) and throw if it is missing or non-numeric.
   TestAuto additionally reads `FileVersion` back off the published `TestAuto.Web.dll` after the publish
   step and **throws if the built version disagrees with the csproj** — a stale stage or an unbuilt
   `<Version>` edit cannot ship a package whose filename lies about the app inside it. The same value feeds
   `/DAppVersion` and the package filename (`TestAuto-Setup-2.5.0.exe`, `CrewChief-Setup-2.0.1.exe`).
   **Consequence:** the in-app update banner fires on ANY component bump, patch included; same-version
   rebuilds are still invisible to the feed, so bump when you mean to release.
3. **Publish** — wipe/recreate `installer\stage\`, then `dotnet publish -c <cfg> -r win-x64 --self-contained true`. CrewChief publishes **two** projects (Web → `stage\web`, Cli → `stage\cli`); TestAuto publishes one (Web → `stage\web`). Non-zero exit ⇒ throw.
4. **Strip what must never ship** — remove operator/dev residue from stage. CrewChief strips `web\appsettings.Production.json`, `web\data`, `web\logs`, `cli\data`, `cli\logs`, then re-points the staged `cli\appsettings.json` `DataFolder` → `..\web\data` (so the shipped CLI sees the same store as the Web app). TestAuto strips `web\logs`, `web\TestResults`, and the environment-overlay appsettings (`Development/development/Production/CommandLine`) — only the base `appsettings.json` ships. Both copy `GETTING-STARTED.md` into stage and assert a sane file count (≥50) to catch a broken publish.

   **`web\Plugins` is stripped and then immediately RE-STAGED** (step 5b, `New-TestAutoInstaller.ps1:146-170`) from each plugin project's own `bin\<Config>` output (`TestAuto.Connect`, `.Matching`, `.Metadata`, `.Records`, `.Utilities`). The publish-emitted copy mirrors the dev tree's never-refreshed `Plugins\` folder, so shipping it produces a box that registers only `DefaultScenario`. A missing plugin assembly **throws** rather than quietly shipping a scenario-less install.

   This pairs with MSBuild machinery in `TestAuto.Web.csproj`: three plugin `ProjectReference`s with `ReferenceOutputAssembly="false"` (`:100-104`) purely to force build order without copying, plus `CopyPluginsToOutput` (`:162`, `AfterTargets="Build"`) and `CopyPluginsToPublish` (`:183`). The latter must run **after** `ComputeResolvedFilesToPublishList` — hooking it before means the SDK skips the app-root copy and startup throws `FileNotFoundException` for `TestAuto.Utilities`.
5. **Compile** — `& $iscc "/DAppVersion=$version" "/DStageDir=$stageDir" "/DOutputDir=$OutputDir" /Qp <iss>`. The three `/D` defines feed `#ifndef` fallbacks in the .iss (so the script also opens standalone in the Inno IDE against an existing `stage\`). Verify `*-Setup-<version>.exe` exists; print its size.

### Version bumping (`-Bump` / `-BumpMinor` / `-BumpMajor`, at most one)

**Identical semantics in both scripts** (aligned 2026-08-12): `-Bump` = patch (`2.5.0`→`2.5.1`),
`-BumpMinor` = minor + reset patch (`2.5.3`→`2.6.0`), `-BumpMajor` = major + reset the rest
(`2.5.3`→`3.0.0`). Passing more than one throws. Each is a **targeted text replace** of `<Version>`
(not an XML round-trip — preserves comments/formatting), written back so the repo reflects the shipped
version; non-numeric ⇒ throw. Only the file differs: `CrewChief/Directory.Build.props` vs
`TestAuto.Web/TestAuto.Web.csproj`.

> [!important] The duplication is deliberate — keep the two blocks in sync
> The bump logic is copy-paired rather than factored into a shared script because CrewChief's installer
> must not reference anything on the TestAuto side of the repo (see [[crewchief-architecture]]'s
> standalone rule). Both scripts carry a "change one, change the other" comment. Editing one half alone
> silently re-introduces the mismatch this alignment removed.

TestAuto has **no** `VersionMajor`/`VersionMinor`/`_VersionBuild`/`_VersionRevision` properties any
more — do not cite them. Nothing in C# reads MSBuild version properties; the runtime path is
`AssemblyInformationalVersion` → `AppVersionInfo.ResolveVersion` → `ToDisplayVersion` (trims to 3
parts) → `IAppVersionInfo.Version`, shown in Help → About, the home Version pill, and the update-feed
comparison. CrewChief's equivalent is `Home.razor.cs:ResolveProductVersion` (same attribute, `+sha`
suffix trimmed).

Without a bump switch the current version is reused (re-running the same version over an installed box acts as a **repair**).

### The `dp*` wrappers (PowerShell profile)

`dpcrewchief -Package [-Bump|-BumpMajor]` and `dpspeed -Package [-Bump|-BumpMajor]` call the respective `New-*Installer.ps1`, then a shared tail (`Publish-SpeedMerchantsPackage`) copies the produced `{ScratchRoot}\*-Setup-<version>.exe` to `{PackageShare}` and prunes OLDER versions of the SAME product. Share copy is best-effort (an unreachable share warns, never fails the build). See memory `reference_package_share_publish`.

## .iss rules that must not be violated

- **NEVER change `AppId`.** It is the identity that makes re-running a newer Setup.exe an **in-place upgrade** instead of a second parallel install. (CrewChief `{{B7A6D3E8-…}`; TestAuto `{{E4F1A9C2-…}`.)
- **Operator state is never in `[Files]`.** CrewChief `{app}\web\data` + `{app}\web\logs`, TestAuto `{app}\web\logs`, are never listed, never deleted on upgrade, and on uninstall are removed only after an explicit prompt whose **default is Keep** (`MB_DEFBUTTON2`). **`Plugins\` is NOT operator state** — it is build output, re-staged from the plugin projects on every package (step 4 above).
- **Upgrade = stop first.** `PrepareToInstall` stops locked binaries before copy. **Both** now stop the
  service first (`StopServiceAndWait` — `sc stop` returns immediately, so it polls the SCM for STOPPED for
  ~30 s: `TestAuto.iss:392`, called at `:539` and `:657`) and then `taskkill /F /T` the Web exe to catch a
  console instance.
- **Service recovery is configured, and the failure FLAG is the load-bearing part.** The TestAuto installer
  applies `sc failure … reset= 86400 actions= restart/60000/restart/120000/restart/300000` plus
  `sc failureflag <svc> 1` (`TestAuto.iss:510-528`). Recovery actions alone fire only for a *crash*; the
  flag is what extends them to the SCM's 30-second **start-timeout** (event 7009), which TestAuto can hit at
  boot while it waits on REST secrets and Hangfire SQL. `start= delayed-auto` (`:502`, `:505`) does **not**
  cover that case on its own — it was already delayed-auto when the failure was first observed.
- **`SetupArchitecture=x64`** under Inno 7 (guarded by `#if VER >= EncodeVer(7,0,0)`), with a 6.x fallback to `ArchitecturesAllowed`/`ArchitecturesInstallIn64BitMode=x64compatible`.
- Both brand everything with the checked-in `profisee.ico` and install to `{sd}\Deploy\<AppName>` by default (dir page still shown).

### TestAuto service mechanics (ported from CrewChief 2026-08-08)

TestAuto.iss carries the full CrewChief service `[Code]` machinery (ServiceExists/CurrentServiceAccount
cache, keep-current-on-upgrade page anchored after `wpSelectTasks`, stop-before-copy, `/SERVICEACCOUNT=`
`/SERVICEPASSWORD=` silent params, `Grant-ServiceLogonRight.ps1` dontcopy — a copy now lives in
`installer\` too) **plus TestAuto-only validation**: `AccountIsLocal` (`.\`, machine-name, bare-name
accounts) is a HARD refusal in both `NextButtonClick` and `PrepareToInstall`; a non-`a*` user part and a
miss in `net localgroup Administrators` (direct members only — nested AD groups invisible) are
confirm-dialogs defaulting No. Tasks are exactly four: `service`, `firewall` (unchecked), `clearsecrets` (unchecked — deletes the
machine store's master.json post-copy/pre-service-start AND writes the `.legacy-migration-done`
marker so the reset can't be resurrected; DB TestAutoSecrets + dataprotection-keys untouched),
`desktopicon` — no CLI, no clipath. `[Run]` console-start carries `Check: not WizardIsTaskSelected('service')`;
finish page opens `/secrets/bootstrap`. Uninstall removes service + env var; keep-prompt (default No)
covers `{app}\web` AND `%ProgramData%\TestAuto`.

### CrewChief-only install mechanics (`[Code]`)

- **Service account wizard page** (`InitializeWizard`, `CreateCustomPage` anchored **after `wpSelectTasks`**). Anchoring it *before* the Tasks page made `ShouldSkipPage`'s `WizardIsTaskSelected('service')` test evaluate against unsettled task state, so the page silently skipped itself every run.

  > [!important] There is **no LocalSystem option** — the enum has two members, not three
  > `TServiceIdentityChoice = (sicKeepCurrent, sicSpecific)` (`CrewChief.iss:154`), and `:151` says why:
  > CrewChief runs its box-prep steps **in-process as the service identity**, and LocalSystem reaches the
  > network as `COMPUTERNAME$` — a principal that can hold no SQL login and no admin rights on any *other*
  > machine. The old "LocalSystem is the deliberate default" reasoning applied to a design that ran box-prep
  > elsewhere; it does not apply now.

  - **Keep the current account** (`sicKeepCurrent`) is offered **only** when the service exists *and* already
    runs as a non-built-in account (`CanKeepCurrentAccount`, `:266`). It is preselected once via a first-show
    `ServiceAcctPagePrimed` flag (`:142`, `:341`) so a later repaint cannot override an operator's choice.
  - `sicKeepCurrent` emits **no `obj=` / `password=`** (`:393`), so an unattended upgrade preserves whatever
    account is in place.
  - The page is skipped **only** when the `service` task is off — not, as before, whenever the service
    already exists.
  - Reaching `sicSpecific` **without** a resolvable account/password makes `PrepareToInstall` **refuse the
    install** — before anything is stopped — rather than falling back to a built-in identity (`:398-407`).
  - `/SERVICEACCOUNT=` + `/SERVICEPASSWORD=` override the wizard entirely.
  - Service state (`ServiceExists` + `sc qc SERVICE_START_NAME`) is read **once** on page entry into
    `RefreshServiceState`'s cache. The previous per-click re-query launched five AV-scanned processes per
    radio click and visibly froze the page.
- A specific account gets **SeServiceLogonRight** granted via the bundled `Grant-ServiceLogonRight.ps1` (extracted to `{tmp}`, `dontcopy` — sc.exe alone can't grant it, else error 1069).
- `ConfigureMachineSecretsStore` creates `%ProgramData%\CrewChief\secrets`, locks the whole `%ProgramData%\CrewChief` tree to Administrators (S-1-5-32-544)+SYSTEM (S-1-5-18) by SID, and writes the machine env var `CREWCHIEF_SECRETS_FOLDER` so the interactive CLI resolves the same store as the SYSTEM service.
  - **Then `GrantSecretsFolderAccess`** (`:439`, called when `ChosenIdentity() = sicSpecific`, `:480`)
    re-admits the chosen account with `(OI)(CI)M` **after** the `/inheritance:r` lockdown. Without it the
    service reads access-denied on its own secret store — and because a bare `File.Exists` reports that as
    `false`, the app concludes "fresh box" and offers to **re-bootstrap over a healthy store**. The
    three-state probe in [[crewchief-secrets]] is the runtime half of this same guard.
- Tasks (`CrewChief.iss:75-79`) — exactly **four**: `service`, `firewall` (unchecked), `clipath` (add CLI to system PATH), `desktopicon`. There is **no `resetsamples` task** (the identifier has zero hits repo-wide); don't add one to docs or scripts. Sample templates are embedded in the Web DLL and installed on demand, not by `[Files]` — re-baselining them means deleting `data\.seed-manifest.json` by hand and re-running an install from the Templates page. See [[crewchief-default-templates]].

## Cross-links

- [[crewchief-secrets]] — the files-only two-tier secret store the CrewChief service exposes at `%ProgramData%\CrewChief\secrets` via `CREWCHIEF_SECRETS_FOLDER` (SecretsRootResolver precedence).
- [[testauto-secrets-management]] — the Profisee-DB `TestAutoSecrets` store the TestAuto installer intentionally leaves to the in-app `/secrets` bootstrap.
- [[crewchief-default-templates]] — the embedded sample steps/workloads/secrets and reference sets seeded on demand (first-run banner / Templates page), which the installer deliberately does not touch.

## There are FOUR of these, not two

The matrix above is CrewChief-vs-TestAuto because those two came first. Two more were built from the same
pipeline and are documented nowhere else:

| Product | Script | Version source | Ports |
|---|---|---|---|
| CrewChief | `CrewChief/installer/CrewChief.iss` | `CrewChief/Directory.Build.props` | 5030/5031 |
| TestAuto | `installer/TestAuto.iss` | `TestAuto.Web.csproj` | 8080/8443 |
| TestDataGeneration | `TestData.Generation/Installer/TestDataGeneration.iss` | `TestData.Generation/Directory.Build.props` | 5045/5046 |
| DataGenerationAndMutation | `TestData.Mutation/Installer/DataGenerationAndMutation.iss` | `TestData.Mutation/Directory.Build.props` | 5047/5048 |

All four use the same **ISCC7-to-6 compiler fallback** and the same bump-and-write-back of the version
source. `DataGenerationAndMutation.iss` is a deliberate **FORK** of `TestDataGeneration.iss` - restated in
full, never a shared include, and with no cross-product references. Do not try to factor them together.

The two TestData products are covered by [[testdata-generation-and-mutation-engine]] and
[[testdata-generation-and-mutation-shape-authoring]].

Two behaviours the newer pair adds:

- **`{app}\samples` ships `onlyifdoesntexist uninsneveruninstall`.** An operator edits the samples in
  place, so an upgrade must never overwrite them and an uninstall must never remove them.
- **`{app}\Claude` (the AI brief) DOES ship and DOES refresh on upgrade** - it is an installer payload for
  an agent working on a deployed box, not operator state.

## The operator-chosen web port - and the write seams are OPPOSITE

All four installers grew an operator-chosen HTTP port with one doctrine: **chosen once, then LOCKED.**

| | Fresh install | Existing install |
|---|---|---|
| Wizard | Live, editable field | **Disabled**, showing the current port |
| `/PORT=NNNN` | Honoured | **Ignored, with a log line** |

The port is read back on upgrade rather than re-asked - TestData's installers parse it out of the service
binPath via `sc qc` / `ParsePortFromBinPath`.

> ### The part that is easy to get wrong
>
> **TestAuto and CrewChief write the chosen port to DIFFERENT files, deliberately.**
>
> | | Write seam | Why |
> |---|---|---|
> | **TestAuto** | **`appsettings.json` itself**, patched post-`[Files]` / pre-service-start by `ApplyWebPortToAppSettings` | An overlay is forbidden here (stale Production overlays once shipped a dev hostname). And because the shipped file **arrives fresh every upgrade carrying the DEFAULT**, the installed port must be read BEFORE the copy and re-applied after |
> | **CrewChief** | **`appsettings.Production.json`** - the overlay it creates ONCE and never overwrites | That overlay is already its machine-local value seam |
>
> This mirrors the inverted appsettings rules the matrix above already records. An agent that assumes the
> two are the same will patch a file the other installer never reads.

`--urls` and `ASPNETCORE_URLS` **cannot help**: `Program.cs` configures Kestrel from `WebUI:HttpPort`,
which overrides them.

Two Inno mechanics that constrain the implementation:

- **`[INI]` and `[Run]` cannot call a function**, so the port reaches them only through scripted constants
  (`{code:GetLaunchBase}` / `{code:GetWebUrl}`).
- **Inno has no forward declarations**, so those scripted-constant functions must be declared *below*
  `ChosenPort`.

**HTTPS is deliberately NOT configurable.** Only the HTTP port is an operator choice.

## Sources

- `CrewChief/installer/CrewChief.iss` — CrewChief Inno Setup script (service/shortcut modes, machine secrets, PATH, firewall, service-account wizard).
- `CrewChief/installer/New-CrewChiefInstaller.ps1` — CrewChief 5-stage build script; `Directory.Build.props` version bump.
- `installer/TestAuto.iss` — TestAuto Inno Setup script (**service mode is the default task** at `:98`; **appsettings.json ships fresh and is always refreshed** — `onlyifdoesntexist` appears ZERO times, see `:107`; firewall; operator-chosen web port written into `appsettings.json` itself by `ApplyWebPortToAppSettings`). *Corrected 2026-09-09: this gloss previously read "shortcuts-only, once-only appsettings", contradicting this skill's own matrix rows — and "once-only" would lead an agent to conclude the installer cannot own the port write, which is exactly backwards.*
- `installer/New-TestAutoInstaller.ps1` — TestAuto build script; 3-part `<Version>` bump in the csproj; built-DLL version verified against the csproj (throws on mismatch); plugin re-stage step 5b.
- `CrewChief/Directory.Build.props:14` and `TestAuto.Web/TestAuto.Web.csproj:18` — the two `<Version>` single sources of truth. Both are bumped every ship, so always re-read rather than quoting.
- `TestAuto.Web/Services/AppVersionInfo.cs` — `ToDisplayVersion` trims to Major.Minor.Patch; `BuildDateUtc` carries the compile timestamp that used to be smuggled into Build.Revision.
- `CrewChief/installer/BUILDING.md` — prerequisites, one-command path, manual build/compile equivalents, appsettings warning.
