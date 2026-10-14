---
name: project_dial_builder_target_plan
description: Dial Workload Builder page v0.6 is the programme's target; board restructured 2026-09-13 into §0 → §6 profiles → §7 builder → §8 trip wires/compare → §1–§5 → §9 run-once composition
metadata:
  type: project
---
**Target.** `Q:\Work\Work\99 Documentation\speedy\dial\02_DialBuilder_Capabilities.html` v0.6 (Artifact aec443ae) is the target the plan must reach. Capability → row map: `speedmerchants\.loop\PLAN-SECTION-D-DialBuilder.md`.

**Why:** the builder replaces hard-coded donor scenario classes with authored dial workloads bound to named, hashed profiles, and a run's fingerprint (its profile hashes) decides whether two tests are identical.

**How to apply:**
- **Order:** §0 load tests → §6 profiles → §7 builder + flow → §8 trip wires / catalogue / compare / resources → §1–§5 → §9 dial step + Business Rules apply, after 50.W1.2.
- **Dispositioned rows:** 56.01–56.06, 58.01 and 54.05 are delivered by the builder. 53.01 and 53.27–53.30 are re-sized at 52.S8.7; the non-records donor scenarios stay.
- **Design rules:**
  - Profiles are read-only once used and change only by Save as new; hash-equal duplicates are refused.
  - The topology hash covers hardware profiles; machine names are Context.
  - The Profisee version is its own profile.
  - Resource series are found by the Prometheus `host` label, with no collector binding.
  - Shuffle children must be independent (produces / needs check).
  - "Stewardship" is not a concept; the sample is Browse-and-edit.
- **Open:** where TestAuto keeps machine profiles (the seed for hardware profiles) is unknown.
- Related: [[feedback_docs_state_why_and_how_not_provenance]], [[feedback_value_picker_always]], [[feedback_dial_up_real_first]].
