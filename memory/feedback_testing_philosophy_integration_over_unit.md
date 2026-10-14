---
name: feedback-testing-philosophy-integration-over-unit
description: "Gene's testing philosophy — unit tests minimal and high-value only, real bugs live in integration; censuses are the exception worth keeping"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 34c06f04-ada7-44f8-a3e4-66dc2a3c5365
  modified: 2026-09-02T16:38:42.374Z
---

**Gene, 2026-09-02:** *"My philosophy on testing is that Unit Tests should be minimal and only of high
value, that real integration testing is where you find the real bugs. Unit Tests add a lot of green
lights but have not significantly improved the quality of the outcome."*

**Why:** a large passing unit count buys confidence it has not earned. The speedmerchants vNext record
is unusually direct evidence — across UoW-8b and 8c, **not one significant defect was found by a unit
test.** Every one came from a live proof: `migrate` never running a migrator (`Invalid object name`),
the orphan sweep terminating live runs, a published view that could not be reshaped, the pause/dial
race, the queue-vs-fleet gap, the UI drifting from the store.

**The sharpest example:** `Provider_ResolvesAllSixMigrators` asserted six migrators *resolve from the
container* and stayed green while the system was broken, because nothing asserted the migrate verb
*ran* them. **Resolution is not invocation.**

**How to apply:**

- **Default to integration/e2e proofs** against real containers and a real store. In this repo they are
  `scripts/chaos/` (K1–K5) and `scripts/e2e/Invoke-*Proof.ps1`, and they are what actually protects it.
- **Do not reach for mocks on the "integration can only hit a race by luck" argument** without checking
  it. This team's own M5 proof takes a real SQL lock, confirms a request is genuinely blocked via
  `sys.dm_exec_requests`, and hits the race window 22 times on demand.
- **CENSUSES ARE THE EXCEPTION — keep them.** Assertions that count registrations, hosted services,
  migrators, view columns or type strings against a literal. They do not find bugs; they **refuse
  silent drift**, and they went red exactly when something moved underneath them three iterations
  running. Cheap and high-yield.
- **Before writing a fault-injection test, ask whether an integration proof reaches the same fault.**
  Applying this cut a planned six-task unit down to three: a fresh-volume migration proof (integration),
  one genuinely-hard partial-write injection, and a census audit.

I proposed the six-task mock-heavy suite; Gene pushed back and the repo's own record proved him right.
See [[project-speedmerchants-uow8b-8c]] and [[feedback-loop-practices-that-caught-defects]].
