---
name: project_vnext_workload_bundle_format
description: "vNext's on-disk workload definition format IS the CrewChief export bundle shape, one shape for both products"
metadata: 
  node_type: memory
  type: project
  originSessionId: 34c06f04-ada7-44f8-a3e4-66dc2a3c5365
  modified: 2026-09-03T19:46:21.071Z
---

Gene, 2026-09-03: *"We want a workload (whether it is for testauto or crewchief) to work the way
crewchief exports work today."*

**The on-disk workload definition format IS the CrewChief bundle format.** Not a definition format
plus a separate export format — one shape. Read at donor HEAD, not from memory:

- **Self-contained by CONSTRUCTION, not by packing.** Every workload step carries its own **inline**
  definition, so nothing outside the workload is depended on. The bundle is just
  `{schemaVersion, exportedUtc, workload}`.
- **`referencedSteps` was deliberately REMOVED.** Importing touches the step library not at all.
  `LegacyWorkloadRefGuard` rejects old bundles that still carry `ref` entries, with a message.
- **Import is always-new** — a same-named workload is never overwritten; a unique name is minted.
- **Preview first**, applying the same validation gates so a preview never promises a failing import.
- **Export WARNS, never fails**: plaintext secrets (step + field, never the value) and
  `RunWorkloadStep` references that will not travel.
- Result objects, never exceptions. `schemaVersion` stays `1.0` on purpose — bumping it would reject
  legacy-but-valid bundles too.

**The cross-product bit that makes this a contract.** In the donor, `TestAuto.Web` carries a
hand-written MIRROR (`CrewChiefExport/CrewChiefWorkloadBundle.cs`) because TestAuto must never
reference a CrewChief assembly — *"the serialized JSON is the ONLY contract between the two"* — and
drift is caught by `CrewChiefWorkloadBundleShapeTests`, which pins property names and the schema
version **literally**. vNext is one product so the mirror collapses, but vNext still exchanges
workloads with existing CrewChief and TestAuto instances, so **the wire shape stays a cross-product
contract and needs its own literal shape census**, for the same reason: nothing else can see the
drift. Same class of contract as the KDF parameters in [[project_crewchief_secrets_shipped]].

**Consequence that reaches beyond export:** self-contained-by-construction constrains the STORES. A
saved workload must already be importable elsewhere with no library resolution, so the vNext step and
workload stores must never write a library reference into one.

Binds tasks A3.2, A3.3, A3.6, A8 and screen 9.16. Full rule with citations lives in
`C:\devops\repos\speedmerchants\.loop\GOAL.md`; amendment banner at the top of
`Q:\Work\Work\99 Documentation\speed-merchants\vNext\Design\A3_StoreReconciliation.md`. See
[[project_crewchief_workload_merge]] and [[project_crewchief_export_wizard]].
