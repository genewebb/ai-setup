---
name: project_metric_version_scenario_profiles_2026-09-24
description: 2026-09-24 approved design - new profile kinds Profisee Version, Target Metric (SQL table + column map to code-declared measured fields), Scenario (identity/tags/typed params/expects) + step-level profiles (step own > workload > caller); gate YVVWUAJgPCowswqPUwLfYm
metadata:
  type: project
---

**2026-09-25: tracker SUPERSEDED, then split by folder.** Requirements rows MP-9..MP-12 and MPQ-19 live in Q:\Work\Work\99 Documentation\speedy\Speedy-Requirements-Tracker.md. Code rows MP-1.2 and MP-1.3a (parked) and MPQ-1..18 live in Q:\Work\Work\99 Documentation\speedy\Speedy-Coding-Tracker.md (it was speedy-tracker.md). The old metric-profiles tracker is an archive.

Gate approved 2026-09-24: https://claude.ai/artifact/YVVWUAJgPCowswqPUwLfYm. Spec file: session scratchpad METRIC-PROFILES-SPEC.md (copy key points here if it is lost).

- Speedy had NO dynamic metric definition (dbo.Metric fixed narrow name/value; 3 producers). "Dynamic metric" = donor TestAuto [MetricColumn] classes + TargetMetricEntity -> now a Target Metric profile.
- Target Metric: warehouse SQL table, grain Detail (per call) | Summary (per step, aggregates); columns map to `measured:<Field>` (code-declared catalogue) | `tag:<key>` | `tags` | `value:<spec>`; create if absent, verify shape, never ALTER; dbo.Metric stays the always-on base.
- Profisee Version: standalone kind; ExpectedVersion, Match Exact/MajorMinor/Major, OnMismatch Refuse(default)/Warn; probed via the resolved Targets REST URL; no REST target = "not checked".
- Scenario: Kind, Description, key:value tags, typed parameters with values, Expects kinds.
- Tags key:value from workload + step + Scenario, step's own wins per key.
- Step-level profiles of any workload kind; per kind step own > workload > caller (like Run As); Target Metric is a list, the step's own list REPLACES the workload's.
- Build order: engine+tests -> requirements amendment `metric-profiles-r1` (chain r1 -> r2 -> this) -> screens -> full suite + redeploy.
- The same day Gene also answered r2's open questions: keep "Copy and edit", keep the built widths, CrewChief import approved, a failed mark does not stop the run.

**Why:** Gene: "a workflow may have any number of target metrics so we may need profiles at the global level and at the step level".
**How to apply:** Screens follow the gate. Every WorkloadDefinition/StepDefinition copy must carry the step profiles. See [[project_crewchief_bundle_import_and_workload_runas]].

**Gene's answers to metric-profiles-r1's 13 blocking questions (2026-09-24, all recommended):**
- Types: safe widening only.
- NOT NULL: refused at workload save and at the run's table check.
- Aggregates: nearest rank.
- Values never truncated or rounded; a row that does not fit is not written and the run is marked incomplete.
- Tags: strict key:value, ordinal keys, step > Scenario > workload, all-tags joined "key:value;".
- Rows: every attempt writes rows; a no-call step writes one row.
- De-duplication: a Speedy RowKey column.
- Version: compared at the expected version's precision.
- Enum is ordered; no Secret type.
- Scenario Kind must be a registered name; a mismatch refuses.
- Unreadable version = mismatch.
- A child inherits the calling step's resolved profile.
- Donor TargetMetricEntity removed.

Status: built into the engine and applied to the amendment (all retired); see State 2026-09-25 below.

**Tracker (2026-09-24):** remaining work is `Q:\Work\Work\99 Documentation\speedy\metric-profiles\METRIC-PROFILES-TRACKER-2026-09-24.md`, rows MP-0..MP-12. Gene runs /clear and then /goal "Do the next open rows of <tracker> ...". The durable copies (spec, gate html, restart script, agent reports) are in `C:\tmp\speedy-metric-profiles\`, because the session scratchpad does not survive.

**State 2026-09-25 (tracker MP-0..MP-8 done):**
- Engine + screens BUILT (uncommitted working tree; Gene commits). Full suite green: Unit 6533/60 skipped, Web 679, Browser 75, Criteria 21, Architecture 21.
- Gene accepted screens R/V/M/S/W live on verify host http://127.0.0.1:5290 (MP-7). Owner Qs 1-18 answered (all recommended); Q19 (AC-TARGETMETRIC-003 child-step Batch value) still open, ask at MP-12.
- Deferred, NOT built: per-work-item rows for fleet LoadWorkload runs + central copy of Target Metric tables (MP-1.3a, needs own spec + gate); run-time step-vs-Scenario-Kind refusal (MP-1.2, waits for a coded scenario step type).
- Amendment metric-profiles-r1 answered (0 errors/159 warnings on overlay) but NOT rebased: library-fix-list-r1 went live 2026-09-24; r2 must rebase + be approved (requirements tracker B4) before MP-9 rebase, then MP-10 clean review, MP-12 Gene approval.
- Review prompt refreshed: `Q:\Work\Work\99 Documentation\speedy\requirements\review\REVIEW-PROMPT-METRIC-PROFILES-R1.md`.
