---
name: project_dial_workload_builder_design_2026-09-13
description: "Dial workload builder planning 2026-09-13 17:30–18:50 (Gene + Fable): nine reusable profiles embedded in the bundle, activity = Sequence/Roll/Shuffle/Step flow on a native fleet interpreter (Elsa deferred), trip-wire rows, static run-profile catalogue with dynamic selection, all 14 questions answered; page v0.4 in speedy\\dial"
metadata: 
  node_type: memory
  type: project
  originSessionId: 9eca9880-07a9-4ace-86c9-8f76baf009ce
  modified: 2026-09-13T22:45:18.615Z
---

Planning conversation only, no code. Sources: `Q:\Work\Work\99 Documentation\speedy\dial\01_DesiredCapabilities.md` (v0.2 + addenda §7–§9) and `02_DialBuilder_Capabilities.html` (v0.4, the fuller review page); Artifact https://claude.ai/code/artifact/aec443ae-9334-49e3-bcaa-14f0aa5cc98c (Version 3). This is the "scenario port, planned after §0 closes" line from PLAN-SECTION-S0-LoadTests.md.

**Goal (Gene 17:33):** author "what each user does" as workload steps, no concrete C# class per test; donor CRUD + Stewardship classes retire on parity. Must also define acceptable responses per step and what a failed loop is.

**Model that emerged, decided (D1–D16 on the page):**
- ONE workload type, two modes: run-once (today's CrewChief) and dial (steps once per user per iteration, fleet-safe step set only). Nesting via a `dial` step in a run-once workload (v1, last).
- NINE profiles, one question each, reused in combination, ALL standalone library objects with list + editor (Q5), EMBEDDED in the bundle as `{name, hash, definition}` beside `parameters` and `activity` (Q14: immutable once run; immutable once embedded unless explicitly refreshed): Topology (roles → machines → collector target; R28) · Targets (typed slots, BOTH secret NAMES `rest.baseUrlSecretName` + `rest.apiKeySecretName` per Q12; global parameters; same-slot step override, visible + hashed; precedence step → workload → targets → named error) · Load (users, scope, ramp, stop = iterations/duration/first; claim size) · Supply (entity, scope, BATCH SIZE, partition Paged/Single/Ticket = TestAuto DataPattern; declared values accepted, no COUNT(*) per Q10; the dataset dial of §7.4) · Shape (attributes → TDM kinds) · **Data Mutation** (renamed from Rules 18:23 — "Rules" = business rules) · **Business Rules** (DQ intent, applied by run-once step, proven by CapturedDqRuleCount; v1 toggle only) · Acceptance (response template = CrewChief HTTP step template reused, per-ATTEMPT metric rows; trip-wire rows Measure×Window×Operator×Threshold, AND inside group / OR between, action per group incl. verdict; sample guard default on % rows; locked stacked-rows editor) · Composite run profile (written; one hash per profile).
- Activity = flow tree Sequence / Roll (weighted one-of, must sum 100, branch metered) / Shuffle / Step. Closed grammar. Native interpreter INSIDE the fleet agent; Elsa stays on the campaign plane (D7 rule 2; Gene: "defer Elsa, fine").
- Run-profile items: catalogue STATIC per build grouped by contributor (Core/Dial/Supply/Records/BusinessRules/Connect/Matching/Resources), SELECTION dynamic from the composition, never split by test type; entry carries Comparability = Key | Context | Result. `CompositeRunProfile` already is a closed sparse catalogue.
- Collectors (Gene 17:47): server names exist so Windows collectors / Prometheus can be joined to the run window; P8.4 resource series per role per rung, P8.5 efficiency view = the SaaS resource-reduction question, equal standing with faster/slower.

**Why:** reuse-in-combination was Gene's repeated ask (17:39); every "should X be in the run profile" question resolved by the one-question test.

**How to apply:** when this becomes board rows (after §0, before gate 61 — Gene has not yet said go), the page's IDs (P1a–P9, X, D1–D16) are the criteria source; never reintroduce "Rules" for value generation; never put batch size in Load or a hostname in code. Related: [[feedback-dial-up-real-first]], [[feedback-value-picker-always]], [[project_vnext_workload_bundle_format]], [[vnext-workflow-engine-agnostic-port]], [[project_vnext_filter_editor_design]], [[reference_speedy_dial_up_measurement_constraints]].

**FILED 2026-09-13 18:5x (Gene took every recommendation 18:49):** 27 rows on the board as §6 (52.S6.1–7, gate 67: profiles library; LIST + DEFINITION-EDITOR patterns BORN in 52.S6.4a/4b, moved forward from 52.S1.3a / §3), §7 (52.S7.1–9, gate 68: builder + flow, records family, value factory, flow interpreter, live stewardship proof), §8 (52.S8.1–7, gate 69: trip wires, run-profile catalogue, Prometheus resources, `dial` step last). Ordered after 52.P2.7, before 52.S1.1 / gate 61. Code rows cal 0.5×; 2,150 plan / 1,220 cal minutes. Section doc `.loop\PLAN-SECTION-D-DialBuilder.md`. 50.B DROPPED (D17). Schedule 321 tasks, published to 402006bb. Page v0.5 has NO open questions (answered ones are folded into the body and deleted — [[feedback_answered_questions_move_to_body]]). Board was concurrently driven by another foreman session (52.S0.3a in flight at filing time).
