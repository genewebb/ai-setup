---
name: perftestdata-generator
description: "Greenfield TestData.Generation solution — 350M-record PDATA-shape generator design (2026-08-17), design doc in vault PerformanceTestData folder"
metadata: 
  node_type: memory
  type: project
  originSessionId: 3cd40a29-e690-4042-949f-87f87bef9487
  modified: 2026-08-23T14:30:19.579Z
---

Design approved 2026-08-17 (doc: `MyWorkVault\99 Documentation\PerformanceTestData\Design_PerformanceTestData_Generator.md`). Goal: generate N (~350M) flat SQL records in configurable PDATA-like shape + per-DBA lookup tables, loaded to Profisee via Connect (Connect side out of scope).

Locked decisions:
- Greenfield `TestData.Generation.sln` — zero TestAuto refs; TestData.Shared NOT referenced (patterns copied: its checkpoint is single-cursor, BulkCopyHelper materializes DataTable — both unfit)
- Engine: synthetic `IDataReader` streaming into parallel `SqlBulkCopy` (TABLOCK, heap, index-after-load)
- ShapeDefinition JSON = data dictionary: per-type freeform counts (Date/DateTime/Ffa/Link/Numeric, PDATA=14 each) + Dba count (PDATA=50) + DbaUniqueValues (~30) + TotalRecords + StartCode (default 100,000,000; PDATA historic 10,000,000)
- Rule-based value gen keyed by ATTRIBUTE TYPE (FieldRule Generator+Options concept ported standalone); PDATA-look defaults; realism preferred, human-friendly not critical
- Determinism: every value pure function of (RandomSeed, code, column) → chunk resume without duplicates; ChunkCheckpointStore (dbo.tGenerationChunk) + post-run Verifier
- NAMING: realistic per-type name dictionaries replace Dba_001_PDATA/MyDate001 ordinals — base pool + modifier composition (BillingAmount) + numeric suffix last resort; ≥500 names/type (first-cut cap 500 attributes per type, e.g. 300 freeform in play); DateTime pool excludes Profisee audit names (CreatedOn/ModifiedOn/UpdatedDate) but ProcessedAt/ApprovedAt/SyncedAt style fine; DBA lookups = {Entity}_{ColumnName} (PDATA350M_Status)
- TYPES: attribute types are Dba, Text, Link, Number, Date, DateTime — each own independent count in Shape. "Freeform" = the CATEGORY (all non-DBA), never a type; legacy CreatePData.json rotated types from one FreeformAttributes total, this does not. No "Ffa"/"Numeric" naming.
- Solution: Engine lib + Blazor Server Web UI (Radzen, CrewChief.Web conventions; shape editor, Start/Stop graceful cancel, live progress GenerationRunState) + Cli (headless, Ctrl+C) + MSTest tests. CrewChief = PATTERN for UI/install/layout (lighter than TestAuto), never a project reference.
- Build gotchas baked into plan: repo-wide Central Package Management (never `dotnet add package`, NU1008), own Directory.Build.props chaining root via GetPathOfFileAbove (else strong-name signing lost) + own Directory.Packages.props incl. mandatory System.Security.Cryptography.Xml, MSTest 3.1.1 so `Assert.ThrowsException` NOT `ThrowsExactly`
- Task 17 = new `dpdatagen` profile command mirroring dpcrewchief/dpspeed (Dev-DataGenRestart in Gene.DevOpsTools.psm1 + function in Microsoft.PowerShell_profile.ps1, shared Publish-SpeedMerchantsPackage tail); use it for builds once it exists
- Inno installer sibling of TestAuto/CrewChief pattern (installs Web+Cli+sample shapes)
- Rollout: local sample (1M) → CORPSQL03 new DB (working name PerfSource), 10M rehearsal → 350M
- PDATA verified shape: 122 cols — Name/Code nvarchar(500), 50× Dba_0NN_PDATA nvarchar(100), 14× date, 14× datetime2(7), 14× FFA + 14× Link nvarchar(1000), 14× decimal(26,8); DBA values 5-char codes, no lookup tables exist today

Plan: `MyWorkVault\99 Documentation\PerformanceTestData\Plan_PerformanceTestData_Generator.md` — 16 tasks, TDD, 3 canonical shape variations (V1 PDATA 50dba/70ff, V2 Wide 10/300, V3 Minimal 1/1) required in all structural tests. User executes via own /myworkflow orchestrator loop (2026-08-17). Solution root: `speed-merchants\TestData.Generation\` (sibling sln). Local smoke = 1M records, PDATA-equivalent shape, ModelSource@14322 (creds in sql-container-credentials.local.txt). Open questions all resolved: sibling location, DBA lookup Name = "{ColumnName} {Code}", numeric default 0–10 @ 8dp.

**AI-assistant brief (2026-08-23):** `TestData.Generation\Claude\CLAUDE.md` ships to `{app}\Claude` — agent-optimized (not prose) brief for turning a shipped sample into a variation; installed as CODE (ignoreversion, refreshed each upgrade) unlike `samples\`. Staged by New-TestDataGenerationInstaller.ps1 (`$claudeSrc`, asserts CLAUDE.md by name) and installed via `#define ClaudeDir` + [Files] + a "Claude Brief" [Icons] shortcut. Companion help page `Documentation\24_ClaudeFolder.md` at /help/claude-folder. Same pattern mirrored in TestData.Mutation — see [[project_datamutation_plan]] for the full shipping note.

Related: [[crewchief-installer-plan]] (installer pattern), [[corpsql03-hardware-profile]] (target box).

**Model-deploy extension (planned 2026-08-18):** `Plan_PerformanceTestData_ModelDeploy.md` in the same vault folder — 11 tasks, emits `DeployModel.ps1` + per-DBA `{Entity}\data\{lookupTable}.json` from the generated SQL schema, creating the Profisee model over REST (DBA entities → main entity → attributes → reference data). Verified wire facts baked into the plan: `POST v1/Entities` / `v1/Attributes` / `v1/Records/{entity}`, header `x-api-key`; `attributeType` 1=FreeForm 2=Domain; `dataType` 1=Text 2=Number(scale) 3=DateTime 4=Date 6=Link; payload precedent = `TestAuto.Utilities\Scripts\JsonData\Metadata\RetailClient*.curl`. SQL alone cannot distinguish Text from Link (both nvarchar) — the builder reconciles SQL against the rebuilt `EntityPlan` for kind. Task 1 is a human-gated live probe for 4 unverified facts (model id resolution, record-create key casing, Content-Type, whether Code/Name auto-create). Main-entity data stays Connect's job.
