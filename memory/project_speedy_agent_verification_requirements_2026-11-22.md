---
name: project-speedy-agent-verification-requirements-2026-11-22
description: "Agent-verification framework from Lauren Tan video: general framework v1 done (4 surface kinds, gates, B1-B8), 5 real assessments; next Speedy v1 assessment, profile, requirements"
metadata:
  node_type: memory
  type: project
  originSessionId: 4dd5f09a-5ddb-4cb7-8a77-b1ee5237e704
  modified: 2026-11-23T16:36:33.128Z
---

Started 2026-11-22. Video https://www.youtube.com/watch?v=zdJKkIrBr_g ("How She Runs 35+ AI Agents", Lauren Tan). Transcripts `Q:\Work\Work\99_Frequent\AIResearch\VerificationSkill\BuildVerificationSkill_Part1.txt`, `..._Part2.txt`.

**Shape (Gene, 2026-11-22):** a general engineering framework first, with NO product names, usable by QA on Portal as their starting point and as a review standard ("like clean architecture"). Then apply it to Speedy. Gene agreed with my pushback: the framework and real use cases improve each other; a framework without a use case is only theory.

**Framework v1:** `Q:\Work\Work\99_Frequent\AIResearch\VerificationSkill\AgentVerification-EngineeringFramework.md` (v0 copy `-v0.md`).
- Contents: P1-P11 tagged Talk / Talk extended / Added; 4 surface kinds with a kind table (screen, CLI, HTTP API, MCP; Gene chose all four); section 4 gates; B1-B8 with B7a skills and B7b MCP descriptions; trust stages; section 9 assessment rubric; Getting started with a paste-ready assessment prompt.
- Review history: r1 found 2 blocking and 11 major on v0. r2 found 0 blocking, 8 major, 10 minor on v1. All r2 fixes were applied but NOT re-reviewed (stop rule).
- Desktop and mobile are declared not covered.

**Gates (Gene):** all repos require a PR to main. Slow browser tests run in nightly QA automation, not on PRs; "you can't run every test or PRs take days". The framework has a merge gate and a scheduled gate; a nightly red counts only if it has a consequence.

**Assessments (Gene chose one per kind):** `...\VerificationSkill\assessments\`. Reports: Speedy and Portal (against v0); CLI = CrewChief.Cli, API = rest-api Gateway, MCP = mcp repo (against a mid v1 draft). Findings:
- speed-merchants has no pipeline file: ADO definition 675 points at a missing azure-pipelines.yml. This is ACCEPTED under owner policy (no pipelines for non-product code, 11/23). The CLI report was reworded to match.
- The Speedy PR pipeline is reported advisory (merge-gate.yml:5).
- The Speedy route count of 182 vs my 47 is unresolved; 29 = routes.json members.

**MCP bug note (Gene approved drafting):** `...\VerificationSkill\MCP-ToolDescription-Defects-2026-11-22.md`, for Gene to forward.

**Done 11/22:** Speedy v1 assessment (`assessments\speedy-assessment-v1-2026-11-22.md`) and Portal v1 assessment. Adoption profile: `...\VerificationSkill\Speedy-AdoptionProfile-2026-11-22.md`.

**Gates:** Tier 1 integrator = merge gate (task check + grader only). Tier 2 nightly = scheduled gate. Both are defined outside the repo.

**Gene's value/cost reorder (11/22), which supersedes "build B4 + feature map with the census":**
1. Cheap fixes: write gates in-repo; run Tests.ReverseProxy and QualityTool.Tests, which never run today; fix the dead CLAUDE.md "Test Tagging" reference; add a non-empty guard to HelpCatalogTests.
2. Minimal census: a skipped battery fails, a type exclusion rule, retire check-route-coverage.mjs and routes.json. Built from NFR-ROUTECENSUS-001; page declarations optional.
3. B2 Screen control command (reuse SpeedyWebHost, BrowserSession, RouteBattery) plus the B7a verification skill.
4. Deferred: B4 Screen.
5. **Approved 19:58:** the thin B1 Screen map is built IN PARALLEL with B2. It uses existing ids (pages have 0 data-testid and 412 `id=`) and a dated pending marker; B2 reads names from it.
   - Three groups: (a) fixes + minimal census, (b) map, (c) B2.
   - The verification skill and the Tier 2 legs are outside the repo and routed separately.

**Other decisions:**
- Census gate: Tier 2 plus a touch rule.
- B7a scope: repo files plus the stream-* and speedy-* skills.

**Drafts written 11/22, in scratch corpus copies; DRAFT; validator at baseline 291:**
- `scratchpad\req-map\quality\NFR-SCREENMAP-001.yaml`, ids in `ids-append-screenmap.txt`.
- `scratchpad\req-drive\quality\NFR-SCREENDRIVE-001.yaml`, ids in `ids-append-screendrive.txt`.
- `ids_append.py` HARD-CODES ROUTECENSUS events: never reuse it for another domain.

**Gene's answers 20:4x:**
- Five exit codes.
- Raw selectors allowed.
- Drive depends on the map.
- Gaps approved, but `drivable` is added to the map now.
- A shared non-test library `tests/Testbed.Browser` (SpeedyWebHost, sign-in, ScreenReach) comes first.
- Pending window 30 days, extendable.
- **Battery host is SEEDED with tracked data now**, so selectors that need data render.
- Touch rule yes for both.

Revision authors applied these. Next: clean-session reviews, Gene approval, merge ids, commit on SMVMTR1, /stream-plan prompt.

**r1 reviews and cross-contract decisions, 22:00-22:30:**
- Both drafts failed r1: map 1 blocking (seed writes to real profile folders) + 6 major; drive 1 blocking (no seeded-start owner) + 8 major.
- Coordinator decisions D1-D6 are in `Q:\...\VerificationSkill\speedy-screen-drafts\cross-contract-decisions-2026-11-22.md`.
  - Order: library, then map/seed (ScreenSeed, ScreenMapFile, SeededSignedInAsync), then command.
  - Confinement: cleared environment and sentinel test.
- Gene's answers:
  - always seeded;
  - restrict outside paths in action scripts;
  - the host names the battery account as owner, the seed adds a 2nd account, and the picker gets mapped;
  - gaps 7-9 accepted.
- Old Portal doc archived to `VerificationSkill\archive\`.

**Filed 11/22 on the SMVMTR1 board:** plan IN-20261123010503-846c (retire routes.json and check-route-coverage, Test Tagging reference, HelpCatalog guard); integrate IN-20261123010506-2a1c (Tier 2 legs for QualityTool.Tests and ReverseProxy).
- Battery has no skip path, so "skipped fails" was dropped.
- The NFR-ENGINEERING-001 exclusion list is Gene's own 10/21 design, so it is kept (F6 needs relaxing).
- Pages carry 173 literal ids and about 2,000 data-* attributes; tests use data-* locators most.

**Estimate given:** 15-25 builder tasks. Laptop `.streams` (stale, 9/27-10/17) shows about 55 tasks/day, median estimate 55 minutes. Requirement review is the real bottleneck.

**Next:** write requirements for items 1-3 on SMVMTR1 (re-read the next group number; it was G41).

**Speedy requirement process (when parts resume):** READY only after a clean-session review with no blocking or major findings, plus Gene's approval. Host commit by remote session on SMVMTR1. Validator baseline 291 errors.

**11/23 final:** map e593b171 (reviews r1-r4) and drive ec8d7022 (reviews r1-r5) are clean, 0 blocking and 0 major, status REVIEW.
- Merged in the corpus copy `scratchpad\req-final` at cf6b209a; validator baseline 138.
- Staged to `\\SMVMTR1\d$\Laptop\speedy-screen-requirements-2026-11-23\`: README with prompt 1 (copy, approve, READY, commit) and prompt 2 (/stream-plan G41 library, G42 map/seed, G43 command), plus MANIFEST and MORNING-SUMMARY (copy in VerificationSkill\).
- Support docs go to repo `docs/quality/agent-verification/`.
- Lesson: the validator needs a clean review of the CURRENT revision before READY, so post-review fixes need a restricted re-review. Review records are outside the digest.
- Open: Tests.ReverseProxy has no gate (Inconclusive without its stack); G38.T001 not done; D10 follow-up REQ-ENGPRAC-064.

**11/23 11:30 shipped.**
- Commit 888dbdf3 on SMVMTR1: both requirements READY, approved by Gene through prompt 1; validator 137 before and after.
- /stream-plan released G41 (4 tasks), G42 (6) and G43 (6), each including a T900 integration task. Plan: `.streams\plans\G41-G43.plan.md`.
- Gene chose G41-G43 FIRST in config.json focus.groups.
- Recorded but not planned: the D10 follow-up (REQ-ENGPRAC-064) and the open review minors.
- Next: watch the build; write the B7a verification skill later.

**Gene 11/23 11:34: no test pipeline is planned ("not sure when or if").** The speed-merchants missing azure-pipelines.yml (definition 675) is an accepted, open-ended gap, so its merge-gate score stays 0. Don't re-raise it as an action item. Gene said "Speedy", but the item was speed-merchants. Speedy's own gate (integrator Tier 1 + nightly Tier 2) is unaffected.
- Items 1-3 and 6 from the 11/23 list (ReverseProxy gate, REQ-ENGPRAC-064 D10, verification skill, G38.T001) were handed to the SMVMTR1 planner by Gene. Item 4 (QA hand-offs) is done.

**Open with Gene:** retire or keep `PortalPlaywright-AgentVerification-Requirements.md`. The Portal report needs a v1 re-rate before QA sees it.
