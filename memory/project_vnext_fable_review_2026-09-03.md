---
name: project-vnext-fable-review-2026-09-03
description: "Independent code-vs-requirements review of speedmerchants vNext 2026-09-03; report vNext\FableReview.md; doc defects fixed; Gene DECIDED 15:09: A2.3e key-file protector required, D9 amended to files + explicit commit action, captured RunProfile immutable"
metadata: 
  node_type: memory
  type: project
  originSessionId: aeb9c2fa-dfa1-44ae-ac2e-b7455a08391c
  modified: 2026-09-03T18:51:06.147Z
---

Report: `Q:\Work\Work\99 Documentation\speed-merchants\vNext\Design\FableReview.md` (2026-09-03, HEAD `5982df8`,
suite 1599/0 failed verified by running it).

**Held up:** R1/R2/R3/R4/R8/R12/R14/R18/R24/R25, D6, D20 pins, all §5b run-profile mechanics, M1–M5 fixes,
masking choke point, A2.3d separation seam.

**Open decisions surfaced (not yet answered by Gene):**
1. §5d mandated a cross-platform KDF/key-file passphrase wrap; A2 shipped `DpapiPassphraseProtector`
   only, Linux falls back to plaintext env var (`SPEEDY_TRAVEL_KEY`). A2 is stamped Complete anyway.
2. Operator `LoadWorkload` lives in SQL `dbo.LoadWorkload`; `IDefinitionVersioning` has no consumer
   in any host — D9 "UI save = commit" is unwired. Decide before UoW-9 editors build on the SQL store.

**Plan gap:** v3 §0 claims "every UoW and task" but has zero rows for R13 family typing, R16 rotation,
R21 census, R22 discovery, R26 CDP fixtures, D7 OTel, D20 digest capture, R10, Phase-3 waves.

**Why:** the delivery log only lists scheduled work, so unscheduled requirements vanish from view.
**How to apply:** when asked about vNext status, check FableReview §3 before trusting §0 alone;
re-verify each ✅ against current HEAD, the report is point-in-time.

Related: [[reference-vnext-plan-doc-v3]], [[project-speedmerchants-uow8b-8c]].

**Follow-up 2026-09-03 15:05:** v3 doc defects (all six) fixed and §0 gained A2.3e/A2.3f + Phase-3 table
P3.1–P3.10 (+ §1 counterpart row). Recs 3 (R5/D9) and §5d remain Gene decisions. Rec 4 (`FleetVerb` onto
`AddSpeedy`) intentionally not done as a side edit — UoW-9a loop is live on the same tree; make it a loop task.
FableReview.md §6 records this.

**DECIDED 2026-09-03 15:09 (Gene):** (1) §5d held — Option B, A2.3e key-file passphrase protector is required, A2 container half open.
(2) D9 amended — definitions are files on disk (LoadWorkload leaves SQL, task A8); UI save = file write only; commit is an
EXPLICIT operator action like backup (screen 9.16), never automatic per change ("makes git painful"); what actually ran =
captured RunProfile in DW, immutable (D8). Line: definitions used to START a run vs what actually RAN.
