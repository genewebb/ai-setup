# MyLoop Analysis

Companion to `MyLoopAnalysis.html` (Archify workflow diagram of the row lifecycle). Every figure below is measured
from `.loop/metrics/events.jsonl` via `Get-Throughput.ps1`, from `Get-ReadySet.ps1`, or from the agent token counts the
harness reports. Where a number is a judgement rather than a measurement, it says so.

Measurement window: 24 h to 2026-09-15 23:08, 38 rows closed.

> **Revision 2, 2026-09-15 23:10.** Revision 1 was written at 20:40 and **three of its headline figures were wrong**.
> They are corrected in place below and the corrections are explained in section 5, because how they were wrong is more
> useful than the numbers themselves. The short version: a cheap instrument answered a narrower question than the one
> asked, and I reported its answer. That happened five times in one evening, which makes it the finding of the night
> rather than an anecdote.

---

## 1. How the loop works now

**One row is one unit of work, and its whole state lives in `<repo>\.loop`.** A fresh session resumes from the files,
so nothing has to be remembered from a conversation.

A row moves through six stages:

1. **Ticket authoring.** A row starts as a defect stated in prose on the board. A ticket author agent turns it into
   three files: `PLAN-<key>.md` (why, task, expected outcome, clause reading, constraints, must-not, write set), a
   grader, and the grader's self-test. Several authors run in parallel; authoring is lead work, not dispatch, so it
   continues while workers run and while the loop is paused.
2. **Two acceptance gates, and neither substitutes for the other.**
   - `Test-Ticket.ps1` is scripted and **refuses only** — it never accepts. It checks that the grader is RED today on
     every clause the ticket names, that any already-green clause is declared an invariant, that the self-test passes
     and carries a declared *trap* stub, and that a `## CLAUSE READING` section covers every clause.
   - The lead then reads every clause. The script's own closing line says why: *"This script cannot tell a clause that
     measures the wrong thing correctly."*
3. **Scheduling.** `Get-ReadySet.ps1` computes the largest set of rows that can be dispatched now without violating a
   dependency, and — the part that matters — names the **first reason every other row is blocked**, bucketed by kind.
   Four dependency kinds are machine-checked: write-set overlap (append-only files exempt), `after` (predecessor rows
   must be closed), `exclusive` (a named resource such as `stack` or `warehouse`, one in-flight holder), and
   `testProject`.
4. **Execution.** `Dispatch-Row.ps1` refuses any violation, then emits a wave. Up to seven `foreman-worker` agents run
   in parallel on disjoint write sets.
5. **Collect and verify.** `Collect-Row.ps1` runs the row's grader, the build, the test suite against a floor, the
   ticket's named crosschecks, and a regression sweep over every closed row whose grader names a changed file. Then a
   **blind verifier** — fresh context, never shown the worker's reasoning — re-derives the property itself.
6. **Close.** `Close-Row.ps1` refuses to close unless the `Residual` field is either `none` or the key of a row that
   **actually exists on the board**. Findings become filed work or they do not exist.

**The principle underneath all of it:** a grader is an instrument, never the verdict. Every defect this loop has found
in its own graders was a clause that read a folder, a function name, a temp path or a file's existence and claimed a
tree, a behaviour, a render or a comparison.

---

## 2. What we tried that did not work

**Fable plans and verifies, opus executes.** The original model split. Superseded 2026-09-13 because Fable burned
tokens on this workload. Replaced by opus everywhere, with Fable reserved for a class where it measurably wins.
*(Re-tested on two seats on 09-15 and the burn did not reproduce — see section 4.)*

**The board's prose as the dependency model.** Ordering lived as `'after 52.S0.4s'` inside the *status* column of the
board tuple. Nothing parsed it. `schedule-order.txt` is display order, not a scheduler. So exclusivity and
build-artifact invalidation lived in one person's head, and the cost was conservative serialisation: **workers averaged
0.58 of 7 seats** while the lead waited whenever unsure.

**Measuring ticket supply by sweeping PLAN files on disk.** This counted dead drafts and the tickets of rows closed
before row records existed, and was structurally blind to every row with no ticket at all. It reported 46 rows short of
a ticket. The true figure, once the sweep enumerated open board rows instead of artefacts, was **196 of 208**.

**Counting broken self-tests by matching a pattern.** Revision 1 said "14 of 74 self-tests carry the shape". **Running
all 78 gives 40 that do not pass** — 9 throwing `self-test anchor not found`, 20 printing `SELF-TEST FAILED`, 6 dying
on a renamed repo file, 5 never reaching a summary. A third death shape nobody had named: `speedy.css` was renamed to
`speedy-crewchief.css`, which kills six outright and shows as a failing clause in five more.

**Self-tests that copy the live repo and mutate it forward.** TODAY is a copy of the working tree, CORRECT is that copy
with the repair applied by anchored edits. The moment the row lands, TODAY equals CORRECT, every anchor is text the row
already replaced, and the file throws before its first case. **52.S0.4v caught the disease it cured**: it repaired
another row's self-test, and its own then died the same way.

**Holding collects defensively.** Correct each time, but it accumulated **122 minutes** of finished-worker time sitting
uncollected in one day.

**Excluding by test project to dodge the assembly lock.** Rejected on evidence: the lock is on output *any* solution
build touches, so the exclusion would serialise every code row.

**Writing tickets in bulk without the gates.** Three rows were ticketed before the gates existed; the scripted gate
refused all three. **Tickets written without the gates are inventory that rots.**

**Three attempts at a row.** A row once burned six attempts over 7.5 hours. Two verifier FAILs now means close on what
passes and carry the findings, or split. Never a third attempt.

---

## 3. What we are trying now

**A typed dependency graph.** `after`, `exclusive` and `testProject` in the ticket frontmatter, enforced by
`Dispatch-Row.ps1`, persisted on the row record. Absent means unconstrained.

*Evidence it works:* it caught two false constraints immediately. One row had been chained behind an unrelated row for
no reason; freed, it ran in parallel and reported **DONE in 5 minutes against a 30-minute estimate**.

***And evidence of exactly what it does not model.*** The graph reads files and named resources. It does not model:
- **the shared build.** A row removing a member and a row updating that member's callers have disjoint write sets and
  are coupled through the compiler. Measured: 52.S0.4y reported DONE with its own grader green, and its collect then
  failed three checks on 52.S0.8's half-landed edit. Re-collected clean once the tree compiled.
- **a grader's own side effects.** 48.RFM2's grader plants a file under `src/Domain`. That is in no write set.
- **shared append-only files.** Closing row A merges its append lines into the census; row B in flight then fails its
  own scope check on a file its worker never touched.
All three are filed as **48.WAVE1**.

**A standing ticket queue, aimed by the blocked-reason census.** Volume is not the target. Six tickets that all want
the same exclusive resource is a queue of one. The target is six accepted tickets **that do not share a blocking
reason**.

**Reversal-built self-tests.** CORRECT is a byte copy of the landed files; BEFORE is built by cutting the repair back
*out*. Such a file survives every later landing. This is now propagating through the authors themselves: one refused to
copy its donor's construction, saying "that is the shape that dies on landing".

**Throughput measurement driving the decisions.** An append-only event log per lifecycle step plus a report. It has now
corrected the lead's own claims **five times**.

**Fable on two seats — measured, pre-registered, and neither adopted.**

| Seat | Fable | opus baseline, same night, same template | Verdict |
|---|---|---|---|
| Verifier, small prose row | 94,910 tok / 35 tools / 300 s | ~108,000 / ~52 / ~400 s | ~12% cheaper, ~25% faster; two real findings no opus run produced |
| Verifier, large row | 99,252 / 47 / 490 s | 115,150 / 45 / 550 s | ~14% cheaper, ~11% faster |
| Ticket author | 356,156 / 93 / 39.5 min | 293,972 / 83 / 48.1 min (sibling row) | **+21% tokens, −18% wall**, and it stopped short once with the ticket undelivered |

**No default changed on any of it.** The author seat is the one worth re-testing: ticket authoring is **69% of one
evening's observed subagent tokens** (1,332,535 of 1,929,876) and 28% of wall time.

---

## 4. What we might still try

Ordered by measured size of the constraint each attacks.

1. **Merge the live-proof rows into one stack window.** Four of eight blocked rows want the same stack and warehouse.
   That is physics, not scheduling: no graph creates a second stack. **This is now the largest single unlock and it is
   a board decision.**
2. **Teach the collect what a wave is** (48.WAVE1): refuse the build and test clauses while a wave-mate is dispatched
   and say so, rather than reporting a failure it has misattributed.
3. **A criterion that runs every self-test** — filed as 52.S0.4x, in flight. 40 of 78 currently fail.
4. **Stop the verifier re-running the build and full suite the collect just ran.** *Tried and rejected on 09-15*: with
   the instruction, tokens rose ~8% and wall doubled. The comparison was confounded by row difficulty, so the cost
   question is open — but what it bought was a verifier that stated precisely what its own shortcut cost, which is
   worth more than the saving would have been.
5. **Fable on the ticket-author seat, properly paired.** Same class, same clause count on both arms.
6. **Recalibrate estimates on SIZE, not class** — see section 5.
7. **Make clauses parse the numbers they check rather than hard-code them.**

---

## 5. Where revision 1 was wrong, and why it matters more than the numbers

**Three corrections.**

**(a) "14 of 74 self-tests carry the shape" → 40 of 78 do not pass.** Revision 1 matched a static PATTERN and reported
it as a count of broken files. Running them finds nearly three times as many, and a death shape the pattern could not
see at all (a renamed CSS file).

**(b) "Actuals run 0.29× estimate, so the open queue is ~8,000 real minutes."** 0.29 is the per-row MEDIAN, which
answers *"how wrong is a typical estimate"* and not *"how much work is left"*. A total is not a row. Three defensible
estimators of the same queue give **8,023 / 9,761 / 13,026** real minutes — a **1.6× spread between honest methods**,
so "≈210 wall hours" was stated far more precisely than the data supports.

Recalibration also failed on the dimension the loop actually uses. Held to one rule fixed before looking — adopt a
factor only where n ≥ 5 and the spread inside the group is narrower than the gap between groups:

| Grouping | Result |
|---|---|
| **By class** (what `Get-Calibration` uses today) | **REJECTED.** Class medians sit inside a band of 0.089 while spread *within* each class runs 0.137–0.694. Class carries no signal. |
| **By estimate size** | **ADOPTED for 3 of 4 bands.** Medians 0.833 → 0.383 → 0.368 → 0.290, strictly non-increasing, largest adjacent gap 0.45, rank correlation ρ = −0.327. |

**A big estimate is mostly fear.** A row estimated over 90 minutes takes about 29% of it and is the *most predictable*
band on the board (IQR 0.087). A row estimated at 30 minutes or less is the one nobody can call — the widest spread of
any group measured, class or size.

**(c) "Hard floor: the lead's serial attention, ~4–6 rows/hour" and "roughly 15 minutes a ticket".** Both were
estimates presented as constraints. Measured over six acceptance reads: **~7 minutes a ticket, about 9 an hour**,
against a measured throughput of 1.54 rows/hour. **Acceptance has roughly six times the headroom the loop is using. It
is not the binding constraint and never was.** The argument for a standing ticket queue therefore needs restating: the
reason to run authors continuously is that 196 of 208 open rows have no ticket, *not* that acceptance would otherwise
become a bottleneck.

What the reading does earn is different and better: **four of six reads produced a finding no script could** — a clause
that delegated its proof to a test nothing required, a grader side effect that would have collided with a row in
flight, a scope decision, and two declared false-RED shapes.

**The pattern under all three.** Every one was an instrument that answered a **narrower question than the one asked**,
and answered it confidently. A pattern match claimed a verdict. A median claimed a total. A wall-clock gap claimed
attention. In the same evening, a write-set check compared one file and claimed a set, and a policy gate ran zero tests
and returned a verdict (now filed as 48.RGD1). **The tell is identical every time: the instrument was cheap to build
and its answer was never checked against the thing itself.** A grader is an instrument, never the verdict — and that
applies hardest to the instruments that measure the loop.

---

## Prognosis

- **Open queue:** 208 rows, 196 without a ticket, ~9,761 real minutes on the band-scaled estimator (range
  8,023–13,026).
- **At the measured 0.6 of 7 seats:** ~271 wall hours. **At 2 seats: 81. At 3: 54.**
- Seat occupancy, not ticket count and not lead time, is the lever. On the current board, four of eight blocked rows
  are waiting on one stack and one warehouse.

**Confidence: 0.6.** The throughput, blocked-reason and calibration figures are measured (0.9). The projection is
weaker: it extrapolates one day onto 208 heterogeneous rows, 14 of which carry no estimate at all, and one row
(6 attempts, ratio 5.25) distorts any aggregate. "Continuous running" is also doing real work in that sentence — the
measured window contains hours where no session was running.
