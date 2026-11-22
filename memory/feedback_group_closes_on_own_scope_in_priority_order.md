---
name: feedback-group-closes-on-own-scope-in-priority-order
description: "Stream groups close on their OWN attributed failures in owner priority order (G1 RefData > G2 Backup > G3 Steps > G4 Workflows > G5 TestAuto > G6 Dial); a later group's red never holds an earlier group's close"
metadata:
  node_type: memory
  type: feedback
  originSessionId: 1429c806-dfdf-4219-a2ca-4982bc5c2e03
  modified: 2026-10-01T19:33:57.653Z
---

Gene, 2026-10-01: "Why can G1 not close until EVERYTHING is green ... that makes no sense", then "We should do the fixes for G1 first" and "I want as close as possible to finish them in priority order that I gave you".

Rule: the close-out still runs the full suites once (the 2026-09-13 rule stands, the run is the evidence). Each failure is attributed by write set. A failure owned by this group or an earlier group blocks the close and becomes a fix row there. A failure owned only by a later group becomes a fix row in that later group and does not block. A failure with no owner goes to the earliest group whose feature it tests.

**Why:** all six groups land on one main. Before this ruling, other groups' breaks were pulled INTO G1 (G1.T24, G1.T25, G3.T193 on 2026-10-01), so G1 grew from 4 to 21 rows and slipped with every red run. None of the 17 run-4 failures was in a G1 write set, and the reference-data Playwright subset was 20/20 green.

**How to apply:** never add a dependsOn from an earlier group's integration task onto a later group's row. Rulings sent 2026-10-01 as IN-20261001193318-31f2/aafd and IN-20261001193348-5ad8/5ada/5979. Related: [[feedback-section-close-requires-full-tests-incl-playwright]], [[feedback-run-suites-once-at-group-close]], [[project-speedy-build-campaign-2026-09-26]], [[reference-stream-claim-order-is-group-first-by-design]].
