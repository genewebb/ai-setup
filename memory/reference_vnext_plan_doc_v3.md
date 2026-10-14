---
name: reference-vnext-plan-doc-v3
description: "vNextImplementation_v3.md supersedes v2 (frozen) as of 2026-09-02; §0 is the delivery log, §1b the MUST RESOLVE list"
metadata: 
  node_type: memory
  type: reference
  originSessionId: 34c06f04-ada7-44f8-a3e4-66dc2a3c5365
  modified: 2026-09-02T16:32:04.297Z
---

**`Q:\Work\Work\99 Documentation\speed-merchants\vNext\Design\vNextImplementation_v3.md` is the live plan.**
`vNextImplementation_v2.md` was frozen 2026-09-02 09:45 and carries a SUPERSEDED banner — do not edit
it; an edit there is lost or, worse, disagrees with v3 with no rule for which wins.

**Two sections were added in v3 and are the ones to read first:**

- **§0 Delivery log** — every UoW and task as `UoW | Task | Description | Status | Start | End`,
  times `MM-DD HH:MM`, kept printable on US Letter. Split into Delivered / In flight / Not started /
  the three UI units / Backlog. **Stamp a row when it starts and again when it finishes, never in a
  batch** — the previous doc's table went unstamped for two whole iterations.

  **Gene re-asked for this on 2026-09-02 16:49: *"I want the documented updated on a frequent
  basis."* He asked because he went looking for the work in flight and it was not there.** A whole
  unit (UoW-9a, the authoring backend, tasks A1–A7) had been created and its first task completed —
  suite 1406 → 1427 — while §0 still showed UoW-9 as fifteen screen tasks, all Not started.

  **Why it drifts, structurally.** The orchestrator loop keeps its own `GOAL.md` and `PROGRESS.md`
  inside the repo's `.loop\`, and those stay current automatically — every gate, every deviation
  note. So the work IS documented, in the place only the agent reads. The plan doc is the place the
  HUMAN reads, and nothing updates it but hand. v3's prose was deliberately written to defer to the
  gates; **a table cannot defer to anything.** It is only true if stamped at the moment.

  **The rule, restated so it is actionable:** stamp Started before dispatching an Executor, and
  stamp Completed in the same turn the gates pass — never at the end of a unit, never "later".
- **§1b MUST RESOLVE** — defects, not features, ordered by how badly each can mislead. All six rows
  carry a status marker.

**The UI units are exploded one task per surface, enumerated from the donor code rather than from
memory**: UoW-9 (CrewChief parity) 15 tasks, **UoW-10 (TestAuto parity) 26 tasks** — it had been a
single line and had never been sized — UoW-11 nine. `SecretsManagement` / `SecretsBootstrap` exist in
BOTH donors and are counted **once**, in 9.8/9.9.

**Write prose that cannot rot.** Three of the four stale things found in v2 were dated statements in
the present tense: *"the containers are stopped — this is the first command of any future session"*,
*"expect 1004+ unit tests"*, *"all superseded by `72e464f` now"*. v3's replacements defer to the gate
instead: the probe says **floor, not equality** and names `regression.ps1` as the authority; the
container line says **probe, do not assume**; the checkpoint bullet points at `.loop\state.json`
rather than listing SHAs. A hand-maintained document beside self-updating gates always loses that
race, so make the prose defer.

Related: [[project-speedmerchants-uow8b-8c]].
