---
name: project_crewchief_smart_seed
description: "CrewChief SampleContentSeeder is now manifest+date-gated smart seeding (Phase 1 implemented) — preserves operator edits, keeps-both on newer ship; supersedes the old \"embedded always wins\" behavior"
metadata: 
  node_type: memory
  type: project
  originSessionId: bc525bea-d92c-43f1-b02b-dd4de1184b90
  modified: 2026-07-24T23:58:25.515Z
---

**UPDATE 2026-07-24 — seeding is no longer automatic at startup.** All four seeders
(StarterTemplateSeeder, SampleContentSeeder, StepDescriptionSeeder, ReferenceDefaultsSeeder) were
removed from `CrewChief.Web/Program.cs` startup and now run ONLY via `ITemplateInstaller.InstallAll`
(`CrewChief.Web/Services/TemplateInstaller.cs`, per-category fault-isolated), triggered from two
places: (1) the Home page one-time first-run banner (`FirstRunBanner` control; checkbox "Install
sample workloads, steps, and reference data" CHECKED by default; `FirstRunGate` marker
`<DataFolder>/.first-run-complete`; upgrading installs with existing content complete the gate
silently — no banner), and (2) the new **/templates** page (nav after Reference Data) with the
per-sample status list (`SampleContentSeeder.GetStatuses()` → NotInstalled/UpToDate/ModifiedKept/
UpdateAvailable/UpdateKeepsEdit) and the "Add Default Templates" button. Installer `resetsamples`
task now takes effect at the NEXT template install, not next start. The backup-location seed-once
entry is the only remaining automatic startup seed. Smart-seed mechanics below are unchanged.

2026-07-20: Implemented **Smart Seed Phase 1** for CrewChief steps/workloads. Spec/plan in Obsidian: `99 Documentation\speed-merchants\planning\Design_CrewChiefSmartSeed.md` + `Plan_CrewChiefSmartSeed_Phase1.md`.

**Behavior change (supersedes old seeder):** `SampleContentSeeder.Seed()` no longer re-asserts "embedded always wins when content differs." It now gates by a **shipped date** (`_shippedUtc` metadata property on each embedded `SampleContent/*.step.json`/`*.workload.json`) against a per-box manifest `<DataFolder>/.seed-manifest.json` (records last-seeded date + content hash per artifact key `steps/<file>` or `workloads/<file>`).

Policy (pure decision in `SeedGate.Decide`): file absent → WriteInPlace; shipped date not newer than recorded → Skip (operator in-place edits persist); shipped newer + on-disk untouched (hash matches) → WriteInPlace; shipped newer + operator-edited → WriteVersioned = keep the edit, write the new ship as `<name>-<shippedUtc>.<ext>` with its internal `name` rewritten to match (distinct record). User-named files never touched; nothing deleted.

**New types** (`CrewChief.Web/Services/Seeding/`): `SeedRecord`+`SeedAction`, `SeedGate`, `SeedHash` (SHA-256 hex), `SeedManifest` (fail-safe load/save), `SampleMeta` (reads `_shippedUtc`).

**Deploy hygiene:** predefined content ships embedded in CrewChief.Web.dll; redeploy must use `robocopy ... /XD data logs` (never copy the runtime `data` folder). Documented in `CrewChief/README.md` "Redeploying" section.

**Tests:** unit — SeedGate/SeedHash/SeedManifest/SampleMeta + `SampleContentSeederTests` (updated: `Seed_SameVersion_PreservesAnInPlaceEdit` replaced the old revert test). Integration — `SeedDataIntegrationTests` rewritten to seed a temp folder then read (was reading a non-existent committed `CrewChief.Web/data` folder → had been failing pre-change).

**Phase 2 (NOT done):** reference-data seeders (tags/drive-map/server-names/config-defaults/step-descriptions) — never-remove keys, add-new, update-predefined-only-if-newer-and-unedited, same manifest keyed `refdata/<set>`. Own plan when picked up.
