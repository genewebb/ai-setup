---
name: project_vnext_a3_decisions_pending
description: "vNext UoW-9a A3 store work (2026-09-03/04) — where the decisions live, what Gene still has to answer (\"load-1.0\" envelope for LoadWorkload files), and the two defaults the loop took without asking (step file is flat not envelope; libraries root optional + resolver)"
metadata: 
  node_type: memory
  type: project
  originSessionId: d4f723cc-0219-41c1-bdce-c280f3084109
  modified: 2026-09-04T12:46:57.425Z
---

**Authority docs (Q:\Work\Work\99 Documentation\speed-merchants\vNext\):** `A3_StoreReconciliation.md` (A3.0
decided 09-03 15:08, amended by A3.0b 21:05; §6 items 13–16 record what A3.1–A3.4 measured/decided),
`vNext_TaskPlan.md` (status), `vNextImplementation_v3.md` §0 (row stamps). Loop state: `C:\devops\repos\speedmerchants\.loop\`.

**Awaiting Gene (blocks A8 only):** A3.0b §3.10 "Decision requested" — a `LoadWorkload` file shares the CrewChief
bundle envelope `{schemaVersion, exportedUtc, workload}` but declares `schemaVersion: "load-1.0"` (CrewChief's
import gate is an ordinal exact-string compare at `WorkloadTransferService.cs:155-156`, so it refuses by name),
vs. expressing a LoadWorkload as a one-step `WorkloadDefinition`. Also still awaiting: A2.3f D1–D10.

**Defaults the loop took without asking (flag if Gene disagrees):**
- A3.3: a saved STEP file is the flat vNext shape (integer root `schemaVersion`), NOT the envelope — the donor's
  `StepBundle` is a multi-step list; the "on-disk = export" rule is a workload rule. Recycle-bin delete not
  ported (plain `net10.0`).
- A3.4b (inserted 09-04, **LANDED iteration 19 09:44**): no library store was composed anywhere; libraries root = optional
  `Speedy:Libraries:RootPath`, default `%APPDATA%\Speedy\libraries` / `%ProgramData%\Speedy\libraries` when
  a service — mirrors `SecretsRootResolver` (A2.2a precedent). One `AddSpeedyLibraries` module, one root.

**Why:** these decisions are recorded in repo-external docs and a loop folder; a fresh session needs the pointer
and the "still open" list without re-deriving them.
**How to apply:** before planning A8 or any UoW-9 screen over the libraries, check whether Gene answered §3.10;
read §6 items 13–16 before touching stores.
- A3.5 LANDED iteration 20 (+20b) 09-04 12:46: `{{$ref:type:key}}` resolves end to end; version 0 = any undeclared file (both donor shapes); `ReferenceRenameService` moved to A3.6b; §5.2 "log the refusal" not met — Infrastructure has no logging package (recorded §6 item 17). WriteAtomic retry (member 12b) built in 20b.
- A3.6a LANDED iteration 21 09-04 13:55: transfer services (TransferResult by kind, one envelope + optional folder, one minter, legacy ref refused on parse). `WorkloadReferenceFinding` DROPPED (vNext has no RunWorkloadStep) — §6 item 18. Next A3.6b: TransferSecretScan (structural ValueSource rule), PlaintextSecretFinding, ReferenceTransferService, ReferenceRenameService, StepLibraryExporter + target folder, shared serializer-settings accessor on JsonFileStore.
