---
name: project-pack-docs-in-app-help-2026-11-06
description: Pack people-docs live ONLY in CrewChief in-app help (category Packs); Connect is the blueprint Matching and CRUD copy; runner scripts checked in
metadata:
  node_type: memory
  type: project
  originSessionId: 34a49909-8fbf-493a-ab83-eee68b7ef6e7
  modified: 2026-11-06T15:55:21.017Z
---

Gene 11/06: CrewChief in-app help is the ONE source for workload-pack docs (category `Packs`, sources
`speed-merchants\CrewChief\CrewChief.Web\Documentation\60_PacksOverview.md` + `61`-`64_PackConnect*.md`). The vault
`Q:\Work\Work\99 Documentation\Connect\01`-`03` are pointer stubs (old text in `Archive\`).

Shape (Gene chose): one shared overview with the BLUEPRINT checklist, then per pack four pages: overview, move to a
new machine, check before a run, run manually (orders Connect 10-13, Matching 20-23, CRUD 30-33). Audience for
move/check/run: a QA tester new to CrewChief, Do / Check / If it fails per step. Every pack must ship
`start/<family>-preflight` (Matching lacks it as of 11/06), `rounds/*.txt`, `README.md`; lint must PASS.
`Packs` added to ApprovedCategories in DocsCatalogTests.

Runner checked in 11/06: `CrewChief\packs\tools\runner\` (Run-Queued.ps1, Register-CliRunner.ps1, run-cc-host.sh,
run-queue.sh with list files). Built and parse/dry-run tested only; not yet installed on a box.

Connect test plan (Gene 11/06): the 26R2 full round = history only. Next 26R4 mid-release, then 26R4 GA; the box
changes with the version. Performance runs ONLY 1M at 4T (`rounds\1m-4t-round.txt`); QA runs 1K
(`rounds\1k-4t-round.txt` or `connect/tests`) plus its own tests, so docs and rounds must serve both. SMVMTR2's
hand-made CLI Runner is not swapped; 26R4 has NO Profisee Windows service and should perform at or better than
26R3 (Gene 11/06; flag it if slower); new boxes use Register-CliRunner.ps1. Matching blueprint work handed off as
vault prompt `Connect\06 Prompt - Matching Pack Blueprint (Preflight + Help Pages).md`.

**Why:** Gene wants Matching and CRUD to start from a known-good template, not from scratch.
**How to apply:** when a pack changes in a way a person notices, update its help pages in the same change; new
packs copy the Connect pages. See [[project-crewchief-workload-packs-2026-11-05-tags]].
