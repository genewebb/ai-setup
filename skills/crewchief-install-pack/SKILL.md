---
name: crewchief-install-pack
description: The CrewChief Install workload pack (CrewChief/packs/install) and its generator gen_install.py - download the latest master build of platform pipeline 293, remove Profisee from an application server, install Server / FastApp Studio / Platform Tools, Profisee Configuration on a new or the existing database, verify, add-ons through the Profisee utilities; install-configure-upgrade is also the building block every pack test runs on its restored base. Use when changing, regenerating, deploying or running the Install pack, install-preflight / install-clean / install-upgrade / install-clean-base-prep, or when a test round must start from a fresh install.
---

# CrewChief Install pack

Repo: speed-merchants, `CrewChief/packs/install` (Gene commits). Built 11/07/2026 from the old CrewChief install
workloads (CORPVM31 setup / uninstall backups) on the pack blueprint (`crewchief-workload-packs`,
`crewchief-crud-pack`). Pack notes: `CrewChief/packs/install/CLAUDE.md`. People docs: CrewChief help pages
`73`-`76_PackInstall*.md`. Plan and rulings ledger:
`Q:\Work\Work\99 Documentation\speed-merchants\planning\2026-11-07-p1-install-pack-plan.md`.

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
| start | `install-preflight` | Secrets present, ADO token finds the latest master build, license + 10 GB on the app server, SQL answers, lists installed products |
| tests | `install-clean` / `install-upgrade` / `install-clean-base-prep` | build-get, remove, programs, configure-new / -upgrade, verify (+ add-ons for clean-base-prep; name kept, no base upgrade since 11/08) |
| internal | `install-build-get` | AdoBuildDownload (skipIfCurrent), unzip, verify >= 3 MSIs, publish to the app server, list MSIs |
| internal | `install-remove(-preview)` | Stop service (runWhen MainServiceName) and IIS, remote PS uninstall (Server, FastApp Studio, utilities: the old workloads' order), delete IIS app + pools |
| internal | `install-programs` | CheckPort Free, three InstallSteps (CredSSP), start WAS, W3SVC |
| internal | `install-configure-new` / `-upgrade` | (DropDatabase) + ConfigureStep with the old CORPVM31 switch set; `-upgrade` Configure timeout 7200 s because `crud-run-start` and every Matching load run it on their restored base (11/08: Configuration writes new service sign-in ids into the DB and the app server, so only the backup configured last works; 400 DATA00030 otherwise). Test-Pack resolves this cross-pack child from the sibling install folder |
| internal | `install-verify` | Health wait, exactly one Profisee Server whose DisplayVersion starts with ProfiseeVersionNumber |
| internal | `install-addons` | Utilities exe on the app server: /Import model, /deploydata archive, /Import users (runWhen per file key) |

## Decisions (do not undo without asking)

- No SetApiKey in verify (API user missing after clean install; pack resets set the key).
- Uninstall by discovery in one remote PowerShell step, because UninstallStep needs exact versioned DisplayNames.
- Build is published to the app server so MSIs install from a local path (no double hop).
- Build source: pipeline 293, `refs/heads/master` only.
