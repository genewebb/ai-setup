---
name: review-whole-subsystem-not-serially
description: "When a reported bug turns out to have multiple causes, review the whole subsystem in one pass instead of reporting \"one more thing is wrong\" across several turns"
metadata: 
  node_type: memory
  type: feedback
  modified: 2026-07-31T13:25:03.236Z
  originSessionId: 26ec27c2-0337-4ce1-86d5-d034196dec19
---

2026-07-31, CrewChief capability-advisor work: the user reported "the icons don't update". I fixed one cause, they retested, I found a second cause, then a third, then flagged a fourth as "still open". Their response: **"Fix this and do a review and stop telling me one more thing is wrong."**

**Why:** each round trip cost them a rebuild, a redeploy and a manual retest. Serially discovering causes converts my incomplete investigation into their wasted cycles, and it reads as a system that is endlessly broken rather than one being fixed. A partial fix that gets shipped and retested is worse than a slightly slower complete one.

**How to apply:** when a symptom has one confirmed cause but the surrounding mechanism is non-trivial, DO NOT stop at the first cause and hand it back. Read the whole seam first — every writer and reader of the shared state, every predicate that must agree with another predicate, every key that must fully identify what it keys. List all defects, then fix them together and report once. Specifically:
- Two predicates that gate the same decision in different places WILL drift — look for the sibling of any condition you touch (this is exactly how the deferral-vs-cache bug happened).
- Any cache/dedup key must fully identify its question; check whether resolution depends on state the key omits.
- If I flag something as "still open", expect to be told to fix it. Either fix it in the same pass or have a real reason it is separate work.
- Verify each fix red-first by temporary revert. On this job that caught a test of mine that passed for the wrong reason (removed a field from `Equals` but not `GetHashCode`, so the lookup missed on a hash bucket rather than on the comparison).

Related: [[feedback_verify_no_guessing]], [[feedback_implement_autonomously]], [[project_crewchief_capability_badge_invalidation]].
