---
name: loop-criteria-regression-gap
description: "The orchestrator-worker loop's gate 6 runs the test suites but never re-checks previously-passing criteria, so a row can silently break an earlier row's grader"
metadata: 
  node_type: memory
  type: reference
  originSessionId: 25a6f180-ace3-4c16-9718-60b837d6c54c
  modified: 2026-09-08T20:05:15.099Z
---

**The loop's regression gate has a blind spot: it runs the TEST SUITES, never the previously-passing
CRITERIA.** So a row can leave an earlier row's grader red and close green, and nobody finds out until
something happens to re-run that grader. Discovered 2026-09-07 16:35 while closing row 59.1a.

**How it showed up.** 59.1a moved the standing-fleet loop out of `src/Cli/FleetVerb.cs` into
`src/Composition/Fleet/StandingFleet.cs`. Two earlier criteria assert fleet behaviour by matching text in
`FleetVerb.cs` — criterion 68 (`u7-8-drivers.ps1`, row 47.F) on the `dials(...)` call, and criterion 69
(`u7-r28-roles.ps1`, row 47.G) on `DecideAsync`, both `AnnounceAsync` calls, the "passes over run" line and
the `dispensers(...)` call. All of it moved. The behaviour was unchanged and every test stayed green (2868),
but both graders went red because they were pointed at the old address.

**And the deeper finding: both were ALREADY red before that row touched anything.** Their receipt-freshness
clauses demand a proof receipt newer than the files the proof exercises:

| Criterion | Receipt | Went stale when | Which row should have caught it |
| --- | --- | --- | --- |
| 68 | `.loop/proof/p6-driver-scope.json` @ 09-06 21:53 | `SqlTransportMigrator.cs` changed 09-07 12:34 | 47.E |
| 69 | `.loop/proof/p7-role-routing.json` @ 09-07 12:42 | `WorkloadLauncher.cs` changed 09-07 13:38 | 47.H |

Two rows closed PASS while leaving an earlier criterion red. Nothing was wrong with the product; the
freshness clause was doing exactly its job, and no gate was listening.

**How to apply — add this to the Verifier's routine at every close:**
1. After gate 6, list the files the row touched, then grep `.loop/criteria/` for any grader naming one of
   them (by path or by receipt dependency) and RUN those graders. A structural clause pointed at a moved
   member is a criteria regression the suites cannot see.
2. When a row moves or renames anything, the graders that assert its old address are part of the row's
   scope. Amend them to read the new home, keeping clauses that are genuinely about the OLD owner pointed
   there (a verb's own command line stays with the verb; its loop's behaviour follows the loop).
3. When a row touches a file that a live proof exercises, that proof's receipt is stale and the row owns
   re-running it. Cheap to do, and it is the only thing that keeps a freshness clause honest.

**Why it matters:** a green close over a red criterion is exactly the false confidence the gates exist to
prevent, and it compounds silently — each such row makes the next one harder to attribute. Related:
[[grader-ordering-clause-indexof-blind-spot]], [[loop-practices-that-caught-defects]].

---

## MEASURED 2026-09-08, and it is far wider than the two criteria above

Closing 59.3g, the Executor was told to "re-run criteria 73–84" — a numbering that does not exist. Instead
of guessing it ran **the entire registry**: of the 23 criteria carrying a recorded baseline, **16 green and
7 RED (ids 9, 11, 13, 18, 19, 20, 21) — every one of them `baseline.passed = true` at the 2026-09-05
preflight.** Three days of closes, seven rotted checks, nothing said so. Id 13 is the same `FleetVerb`
drift described above, still unrepaired; 18–21 all fail on a "compose.yaml gained a Libraries key"
assertion. The per-row habit above catches only what the current block touches — it caught the census
criterion because I re-ran the installer block, and caught none of the other six because I never ran
outside it.

**A naive full sweep is NOT the fix.** Running all 88 criteria reports 31 red, and most of those are
correct: a criterion authored for a row not yet dispatched is *supposed* to be red — that is grader-first
discipline working. A sweep that cannot tell "not built yet" from "was working and broke" produces a number
nobody acts on, which is how this rotted in the first place.

**The fix is `.loop/tools/Invoke-CriteriaSweep.ps1`** (written 2026-09-08 13:20). It keeps
`criteria-state.json`: a criterion **ever observed green** is expected to stay green and a red one is
reported as **REGRESSED** (exit 1); one never yet green is reported as **OPEN** and does not fail the
sweep. It seeds `everGreen` from `CRITERIA.json`'s recorded preflight so 09-05's greens count from the
first run, and it reads `SM_SA_PASSWORD` from the **User** scope (59.3e made it required; a plain `$env:`
read misses it in a shell started before it was set, which produced two phantom failures during 59.3e's
close). Run it at every close — that is now part of gate 6, not an extra.

**Three seeding refinements, each forced by a wrong answer the sweep gave before it gave right ones.**
1. **Criteria from CLOSED rows must be seeded ever-green.** Only `CRITERIA.json`'s 23 carry a preflight,
   so eight `u7-*` criteria from closed 47.x rows were adopted as "never green" and filed under OPEN —
   the bucket nobody reads. Default inverted: registered ⇒ expected green.
2. **…but only if REGISTERED.** The second sweep then called `inst-6` a REGRESSION — a grader I had
   written forty minutes earlier for a row still in flight. Membership of `criteria-uow9a.json` is the
   clean discriminator: a grader authored after that snapshot has by definition never closed a row.
3. **Some criteria can only be judged between iterations.** `inst-0-plan`, `u7-0-plan`, `u7b-0-plan`,
   `u9-0-plan`, `p3-0-plan`, `w1-0-plan` all assert the worktree MATCHES the loop baseline. Two of them
   oscillated green→red inside an hour purely because an Executor was mid-edit. They are now SKIPPED
   with the reason said out loud when `git status --porcelain` is non-empty — reporting them either way
   trains the reader to ignore the sweep.

**CADENCE — Gene's decision 2026-09-08 16:01, after being told a full pass measures 30–35 minutes (timed
twice):** *"just run the full sweep once a day then and we will fix as we go."* So it is a DAILY rhythm,
not a per-close gate. `Invoke-CriteriaSweep.ps1 -CheckDue` exits **10** when no unfiltered pass has
completed in 24 h and 0 otherwise — run it at a close, and kick the full sweep off in the background when
it says due. Only an UNFILTERED run records the marker (in its own `sweep-last-full.txt`, not in
`criteria-state.json`, which is rewritten wholesale and would clobber across concurrent runs): a
two-second `-Filter 'b3*'` must not satisfy the daily rhythm.

**And the fix Gene actually asked for, which matters more than the cadence:** *"If there is a way to have
a prep test that setups everything for the 66 so that the time is substantially smaller long term that
would be better anyway."* Measured composition of the 91: **66 invoke `dotnet test`**, 20 are pure text
censuses, 11 touch the database container, 11 touch Docker. So the sweep is 66 sequential test runs each
paying restore-and-build for a handful of tests. **40 of the 66 are the same two lines** and **no
criterion dot-sources anything**, so a shared `Invoke-FilteredTests` honouring an "already built" signal
is both easy and worth it. Row **59.3i**. Keep the vacuous-pass assertion (PRESENCE of a `Passed!`
summary and its floor) inside the helper, and keep the 11 database criteria SERIAL — they create and drop
catalogs on one container.

**The debt the first sweep found was mostly mine.** Seven `u7-*` reds were 59.3e editing 23 proof
scripts and me refreshing only one receipt at its close — repaid by `.loop/tools/Invoke-ProofRefresh.ps1`
(six proofs, sequential because they fight over the standing stack, 21 minutes, all green). One was my
own grader pinned to an exact five-type signature that a later row legitimately widened. Only the
remaining seven were real drift, and four of those are a stale RULE rather than broken code.
