---
name: project_speedy_requirements_system
description: The machine-readable requirements system for the 4-app → Speedy consolidation; lives at Q:\Work\Work\99 Documentation\speedy\requirements; YAML + JSON Schema; first 10 artifacts (Secrets domain) are the templates; restart prompt in the folder
metadata: 
  node_type: memory
  type: project
  originSessionId: 9ad0f53c-a8d0-4663-b061-8c8173fdca68
  modified: 2026-09-17T21:34:33.137Z
---

**Requirements are now the authoritative source, separate from implementation.** Gene, 2026-09-17: start over from
scratch, salvage everything, turn ALL requirements into high-quality machine-readable artifacts; unclear ones go to a
backlog he answers. Location agreed: `Q:\Work\Work\99 Documentation\speedy\requirements\` (own git repo, initialised;
I never commit). Consolidating CrewChief, TestAuto, TestDataGeneration, DataGenerationAndMutation
(`C:\devops\repos\speed-merchants`) into Speedy (`C:\devops\repos\speedmerchants`).

**Shape (settled):** YAML canonical, JSON Schema 2020-12 validates (`schemas/common.schema.json` + 8 type schemas).
Eight types: CAP / FEAT / MIG / API / DATA / NFR / ADR / UX, one file each, `TYPE-DOMAIN-NNN` permanent IDs, refs by ID.
Five blocks kept apart: `source_behavior` (facts) / `requirements[]` (level MUST…MAY) / `architecture`+`decisions` /
`assumptions` / `open_questions` (`blocking` ⇒ not READY). **MIG answers four questions by field:** exists? → `legacy[]`;
which app(s)? → `legacy[].application`; changed and why? → `changes[]` with ADR; started and where? →
`implementation{status, locations}`. `disposition` PORT/MERGE/REDESIGN/REPLACE/NEW/RETIRE mandatory.
**Figures never in prose → `metric`; citations `{file, symbol}` not line numbers** (measured 59% line drift in the old
ticket form). Acceptance = given/when/then + `counterexample{state, disposition CAUGHT|ADMITTED}`.

**Done 2026-09-17:** `RequirementDesign.md`, 9 schemas, 10 artifacts (Secrets + `CAP-SPEEDY-001` programme root
carrying the deliverable/date/budget/stop-rule/first-cut-DoD questions nobody had asked), `manifest.yaml`,
`REQUIREMENTS-RESTART-PROMPT.md`. **Next:** validator+compiler as `tools/Requirements.Cli` + `tests/Tests.Requirements`
in speedmerchants (YamlDotNet + JsonSchema.Net); regenerate `BACKLOG.md`; tranche 0 (programme/sections) → ADRs from
plan v3 §5b–5e / GuidingDocument §8–9 / A6 → capabilities from donor code → features.

**Why:** measured 93% of 207 open board rows had no checkable requirement; three hand-copies drifted; facts,
requirements, decisions and unknowns were indistinguishable paragraphs; no artifact stated what the programme delivers
or by when.

**How to apply:** start from `REQUIREMENTS-RESTART-PROMPT.md` in the folder. Never invent a donor path or a count —
verify, or file a `Q-*`. The loop (`.loop\`) is a separate, parked stream — see
[[project_loop_paused_restart_here_2026-09-17]]. Related: [[reference_vnext_plan_doc_v3]],
[[feedback_value_picker_always]], [[feedback_ui_port_characterise_and_uxreview]].

**2026-09-17 20:20 update.** Old samples/schemas/manifest/reviews moved to `Q:\Work\Work\99 Documentation\speedy\archive\`
(OUTSIDE the requirements git repo, which has zero commits). `RequirementDesign.md` rewritten clean (no history) with Gene's
decisions: hash = normative definition only (status/revision/approval/port coverage/evidence excluded); candidates permanent,
completed state ACCEPTED; PORT forbids change/combine/replace/new; cross-artifact MET- ref = whole-artifact prerequisite;
ID grammar KIND-DOMAIN(hyphens ok)-NNN 3 digits; disposition on target feature, MIG- only when spanning features; new target
carries no inclusion; treatment enum unified (7 values, "not ported" = retire); rows have local `key`; ids.yaml = event log;
evidence file holds attempts[]; routine decisions local, ADR when warranted. Awaiting Gene approval; schemas/templates/samples
not yet aligned. Gene wants FINAL docs, no revision history or provenance inside them.
