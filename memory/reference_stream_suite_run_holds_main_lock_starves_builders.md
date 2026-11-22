---
name: reference_stream_suite_run_holds_main_lock_starves_builders
description: "Builders reading 0 claimable for hours can be the group suite run holding main-grader.lock, which blocks every author RED rerun, so no new tickets land"
metadata:
  node_type: memory
  type: reference
  originSessionId: 54d5e70d-30c2-46df-aa1a-24c7b26da1ae
  modified: 2026-10-02T16:06:50.548Z
---

On 2026-10-02 the owner had 6 builders running while the page showed 2 to 5 live with 0 claimable. There were two separate causes:

- **Display.** Get-StreamStatus counts a session as live only after it writes tasks.json. An idle builder writes nothing, so it is not shown. Kit item IN-20261002150214-6ee3 asks for an idle heartbeat.
- **Supply (the real cause).** All 17 ticketed build rows bottomed out on 4 root rows. Their tickets were already written, and each row's last history note said "RED rerun queued behind G2 suites run 4 (main-grader lock)". The integrator held `.streams\main-grader.lock` (Enter-MainTreeLock, lib\Streams.ps1:575) for the whole suite run, about 2.5 h, because the Browser suite alone takes 1h18m to 1h29m.

**Why it matters:** I first blamed one author serially holding 4 roots and nearly filed a "spread roots" item. That would not have helped, because every author waits on the same lock.

**How to apply:** when builders starve, read the last history note on each blocking root before blaming authors. Check `main-grader.lock` age and the newest `*.Browser.txt` log. A testhost at near-zero CPU whose child dotnet and node processes keep respawning is still progressing, not hung. Owner ruling IN-20261002150859-0d59 moves suite runs into a snapshot worktree.

**Second, structural cause:** the author sort ranks by the row's OWN group, so a G5 root that blocks G3 rows is authored only after every G3 row. Tickets then sat for days on unticketed roots: G3.T210 since 10/1 on G5.T061, G6.T071 since 9/29 on G6.T109 (never touched). Owner ruling IN-20261002153754-be85: the author rank is the minimum group rank over the row and everything that depends on it, transitively.

**Third cause, and the owner's fix:** author RED ran on the single main tree, so 23 releases queued behind one lock. Gene's idea (IN-20261002160453-ce2a): release without RED, and make RED the builder's FIRST step in its private worktree at HEAD. A failed RED bounces the task back to planned. Buffer rule (IN-...-9384): keep claimable at 2x live builders, and raise a "pipeline dry" flag when below.

**Builder picks ALL tests (owner ruling IN-20261002160643-741d, chosen over my "author test + builder impact tests" recommendation):** the ticket states the acceptance clauses only. The builder writes or chooses a test per clause, runs it RED, implements, then runs the clause tests plus the existing tests that cover the files it changed. The blind verifier refutes the record. The grader ran only targeted tests, never all tests; it held the lock only because it compiled the main tree. Related: [[reference_stream_board_eta_is_chain_not_calendar]].
