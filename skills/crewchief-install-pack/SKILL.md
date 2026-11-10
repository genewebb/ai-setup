---
name: crewchief-install-pack
description: The CrewChief Install workload pack (CrewChief/packs/install) and its generator gen_install.py - download the build under test of platform pipeline 293 (AdoBranch / AdoBuildId from the caller, else the reference branch and its latest build), remove Profisee from an application server, install Server / FastApp Studio / Platform Tools, Profisee Configuration on a new or the existing database, verify, add-ons through the Profisee utilities; install-configure-upgrade is also the building block every pack test runs on its restored base. Use when changing, regenerating, deploying or running the Install pack, install-preflight / install-clean / install-upgrade / install-clean-base-prep, or when a test round must start from a fresh install.
---

# CrewChief Install pack

Repo: speed-merchants, `CrewChief/packs/install` (Gene commits). Built 11/07/2026 from the old CrewChief install
workloads (CORPVM31 setup / uninstall backups) on the pack blueprint (`crewchief-workload-packs`,
`crewchief-crud-pack`). Pack notes: `CrewChief/packs/install/CLAUDE.md`. People docs: CrewChief help pages
`73`-`76_PackInstall*.md`. Plan and rulings ledger:
`Q:\Work\Work\99 Documentation\speed-merchants\planning\2026-11-07-p1-install-pack-plan.md`.

Every input carries a `"default"` (Gene 11/10, hand runs; `INPUT_DEFAULTS` in `gen_install.py`): `{{$ref:install/environment:<key>}}` for the version keys, `{{$ref:install/build:AdoBranch}}` for AdoBranch, blank for AdoBuildId (blank = latest build; the one name on the Test-Pack `$HandRunNoDefault` allow-list). A default is used only when no caller supplies the value. A new input needs an `INPUT_DEFAULTS` entry; Test-Pack rule R-handrun checks it.

## Regenerate (never hand-edit a workload)

```powershell
Remove-Item -Recurse C:\devops\repos\speed-merchants\CrewChief\packs\install\workloads, C:\devops\repos\speed-merchants\CrewChief\packs\install\reference-kv
python <skill>\scripts\gen_install.py C:\devops\repos\speed-merchants\CrewChief\packs\install
pwsh C:\devops\repos\speed-merchants\CrewChief\packs\tools\New-PackCatalog.ps1 -PackRoot C:\devops\repos\speed-merchants\CrewChief\packs\install -Family install
pwsh C:\devops\repos\speed-merchants\CrewChief\packs\tools\Test-Pack.ps1 -PackRoot C:\devops\repos\speed-merchants\CrewChief\packs\install -Family install
```

`catalog-meta.json` (estimate per test) is hand-kept at the pack root; `New-PackCatalog.ps1` rewrites `catalog.json` from it, `tests/` and `rounds/`; the lint fails while it is stale.

`rounds/`, `README.md` and `CLAUDE.md` are hand-written and survive a regenerate. `scripts/health.ps1` is the CRUD
pack's health wait.

## Safety (hard rules)

- `install-clean`, `install-upgrade`, `install-clean-base-prep`, `install-remove` and `install-configure-new`
  uninstall or drop the Profisee database. Run them only with the
  owner's go-ahead, only when no run uses that box (`status.json` not Running).
- Safe any time: `install-preflight`, `install-remove-preview`, `install-build-get` (writes only the download and
  publish folders).
- Never print secrets: the preflight checks presence only and redacts 32-hex strings from Azure DevOps errors.

## Workloads

| Folder | Workload | Does |
|---|---|---|
| start | `install-preflight` | Secrets present, ADO token finds the latest build of install/build:AdoBranch, license + 10 GB on the app server, SQL answers, lists installed products |
| tests | `install-clean` / `install-upgrade` / `install-clean-base-prep` | build-get, remove, programs, configure-new / -upgrade, verify (+ add-ons for clean-base-prep; name kept, no base upgrade since 11/08) |
| internal | `install-build-get` | AdoBuildDownload (skipIfCurrent), unzip, verify >= 3 MSIs, publish to the app server, list MSIs |
| internal | `install-remove(-preview)` | Stop the Windows service(s) of the installed Profisee found on the app server itself (name or display name starts with Profisee, program under the installed Profisee folder; none = nothing to stop; independent of MainServiceName) and IIS, remote PS uninstall (Server, FastApp Studio, utilities: the old workloads' order), delete IIS app + pools |
| internal | `install-programs` | CheckPort Free, three InstallSteps (CredSSP), start WAS, W3SVC |
| internal | `install-configure-new` / `-upgrade` | first step "Configuration Manager Supported" refuses `ConfigurationManagerKind` = `new` (text from `install/environment:ConfigurationManagerNewRefusal`); then (DropDatabase) + ConfigureStep with the old CORPVM31 switch set; `-upgrade` Configure timeout 7200 s because `crud-run-start` and every Matching load run it on their restored base (11/08: Configuration writes new service sign-in ids into the DB and the app server, so only the backup configured last works; 400 DATA00030 otherwise). Test-Pack resolves this cross-pack child from the sibling install folder. Both end with a `RunWorkloadStep` of `install-api-key-set` (Gene 11/09: Test-Pack rule R-key, every family, no exceptions: a workload that runs Configuration or restores the Profisee database sets the API key itself afterwards); both take `MainServiceName` as an input for it |
| internal | `install-api-key-set` | Same shape as `crud-api-key-set`: stop Main service (runWhen) + W3SVC + WAS, SetApiKeyStep (`RestKeys:ProfiseeRestKey` for `ConnectRuntime:ApiKeyUserName`), start WAS + W3SVC + Main service, health wait, verify through the gateway (`v1/Entities`) and the Data service (`v1/Rules?PageSize=1`). Reads `install/machines`, `install/instances`, `install/databases` keys already there; input `MainServiceName` |
| internal | `install-verify` | Health wait, exactly one Profisee Server whose DisplayVersion starts with the ProfiseeVersionNumber input |
| internal | `install-addons` | Utilities exe on the app server: /Import model, /deploydata archive, /Import users (runWhen per file key) |

## Decisions (do not undo without asking)

- Version keys (multi-version lanes, 11/09; decisions D6, D11, D12, D17): `ProfiseeVersionNumber`, `MainServiceName`,
  `ConfigurationManagerKind` (`classic` default, `new` refused) are globals of the four roots (`install-preflight`
  has only `InstalledVersionMustBe`, default `""` = no check, plus the step "Installed Version Matches The Lane"),
  each `{{$ref:install/environment:<key>}}`; every workload below a root (`install-remove`, `install-configure-*`,
  `install-verify`, `install-addons`) declares them as `inputs` and gets the value from its parent. A caller's `--param`
  (TestAutoManager lane) beats the root's global. `Test-Pack.ps1` rule R-root enforces it (`install` is in
  `$VersionAwareFamilies`). Release names cannot sit in a workload (lint), so the D17 refusal text lives in
  `install/environment:ConfigurationManagerNewRefusal`. crud (`crud-run-start`) and matching (`*-scenario1-load`)
  call `install-configure-upgrade` with these three as step parameters.

- No SetApiKey in verify (API user missing after clean install; pack resets set the key).
- Uninstall by discovery in one remote PowerShell step, because UninstallStep needs exact versioned DisplayNames.
- Build is published to the app server so MSIs install from a local path (no double hop).
- Build source: pipeline 293. The test workloads (install-clean, install-upgrade, install-clean-base-prep) carry globals
  `AdoBranch = {{$ref:install/build:AdoBranch}}` and `AdoBuildId = ""`; `install-build-get` declares both as inputs and its
  download step uses `branch: {{AdoBranch}}`, `buildId: {{AdoBuildId}}` (CrewChief build with AdoBuildDownloadStep.BuildId,
  11/09). A TestAutoManager round passes `--param AdoBranch=... --param AdoBuildId=...`, which beats the globals (verified
  11/09 with a two-workload fixture; a blank global resolves to empty). Run alone = reference branch, latest build.
  install-build-get alone now needs both inputs (install-preflight shows the newest build).
