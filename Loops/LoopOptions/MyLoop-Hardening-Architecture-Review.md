# MyLoop Reliability Hardening — Architecture Review

Companion to `MyLoop-Replacement-Verdict.html` (KEEP MYLOOP). This is the pre-code review the hardening assignment asks
for: per mechanism, the current vulnerability with file:line, the borrowed pattern, the adaptation to MyLoop, the invariant
it establishes, the failure test that proves it, and the performance risk. Then the row decomposition the loop will run.

Every line number below was read from the installed scripts (`~/.claude/skills/myloop` → `Q:\Work\Work\03 Shared\work-ai\skills\myloop`)
on 2026-09-16 and the three headline defects were re-reproduced on a scratch copy of the live `.loop` before anything was planned.

## 0 · What was verified before planning

| Hypothesis from the verdict | Verified how | Result |
|---|---|---|
| JSON state is written in place | `RowCommon.ps1:34-36` `Write-Json` = `File.WriteAllText`; `:135` `Write-Row` and `:78` `Set-ForemanState` call it; `lib/LoopCommon.ps1:404` snapshot via `Set-Content`; `.loop/tools/Close-Row.ps1:77,82` two more in-place writes; `Write-Schedule.ps1:354-356` two more. **17 in-place sites, 0 temp+rename.** | CONFIRMED |
| A torn file stops the whole loop | scratch copy, row `52.S0.4z.json` truncated to half → `Reconcile-Rows` exit 1, `Get-ReadySet` exit 1 (`ConvertFrom-Json` at position 139); `dispatched.json` truncated → `Reconcile-Rows` exit 1 | CONFIRMED (F8, F9) |
| Concurrent writers lose updates | `RowCommon.ps1:223-229` `Update-DispatchedFile` is read-modify-write with no lock; `Dispatch-Row.ps1:240` rewrites `wave.json` from only its own rows. 20 `Start-Job` writers all landed (jobs start ~1 s apart, so no overlap); the verdict's two-process `Dispatch-Row` run lost one. The race exists by construction; the grader must use simultaneous processes with a start barrier. | CONFIRMED by code; timing-dependent |
| Dispatch can strand a row | `Dispatch-Row.ps1:176` row record → `:177` snapshot → `:186` dispatched.json → `:187` event → `:240` wave.json. A crash after `:176`: `Reconcile-Rows.ps1:33` prints `NOT in dispatched.json`, `Dispatch-Row.ps1:66` refuses (`already dispatched`), `checks/code.ps1` fails constraint (no snapshot). Scratch F1 record: flagged, nothing repairs it. | CONFIRMED (F1) |
| Close can strand a row | `Close-Row.ps1:81-83` board close moves the dispatched entry into started.json FIRST; `:93-99` row record closed AFTER. Crash between: row `collected`, entry gone; retry throws `dispatched.json has no entry` (`tools/Close-Row.ps1:62-64`). | CONFIRMED (F6) by reading |
| LOST is manual | `Reconcile-Rows.ps1:35` only prints `OVERDUE ... if gone, -MarkLost`; `:11-16` is the only writer of `lost`. 4 LOST attempts on record, all hand-marked, one (`52.P1.3b`) with no `lostAt`. | CONFIRMED |
| Stale writers overwrite newer state | No `version` on any of 105 row records; `Write-Row` writes whatever object the caller holds. | CONFIRMED |
| Finished workers wait for collection | `throughput.md`: a finished worker not yet collected **237 min** in the last 24 h (median 2, P90 16 per row). Collection is SKILL step 10, run by the lead by hand per row. | CONFIRMED |
| No cycle diagnosis | `Get-ReadySet.ps1:151-155` reports `waits on X (no row record)` per edge; nothing walks the graph. | CONFIRMED |

## 1 · Mechanisms, one block each

### R1 · Atomic state writes + quarantine
- **A. Vulnerability.** `RowCommon.ps1:34-36` (`Write-Json`, every row record, `foreman-state.json`, `dispatched.json`, `actuals.json`, batch records, `wave.json`, `artifact-urls.json`), `lib/LoopCommon.ps1:404` (snapshots), `.loop/tools/Close-Row.ps1:77,82` (`started.json`, `dispatched.json`), `Write-Schedule.ps1:354-356` (`schedule.json`, read by `Get-ReadySet.ps1:71`). A crash mid-write leaves half a file; `Read-Json` (`RowCommon.ps1:37-40`) throws and every script dies (`Get-AllRows` `:136-138` reads every record on every wake).
- **B. Borrowed.** Standard temp+rename (Superharness's SQLite gives it for free; AIWorkHub's ledger append lacks fsync — we do better than both on the file side).
- **C. Adaptation.** `Write-Json` writes `<file>.tmp.<pid>.<nonce>`, `FileStream.Flush(true)`, then `File.Move(tmp, file, overwrite:true)` (MoveFileEx REPLACE_EXISTING on NTFS: the old bytes or the new bytes, never a mix). `Read-Json` that meets bytes it cannot parse MOVES the file to `.loop/rows/_quarantine/<name>.<stamp>.torn` (never deletes), appends a `torn-file` event, returns `$null`; `Get-AllRows` skips it with one WARNING line naming it; `Reconcile` lists quarantined files as `RECOVERY-REQUIRES-HUMAN` until R6 reconstructs them from the journal. Stale `*.tmp.*` files from a crash are swept into the same quarantine, never deleted. `tools/Close-Row.ps1`, `Write-LoopJson`, `Write-Schedule.ps1` get the same pattern.
- **D. Invariant.** I1: an authoritative file is always the old valid version or the new valid version.
- **E. Failure test.** Kill the writer between the temp write and the move (crash point `write-before-move`): the authoritative file parses and equals the previous version; the temp is quarantined by the next wake. Truncate a row record by hand: `Sync-Board` prints one WARNING and a normal OWED list; `Get-ReadySet` still answers.
- **F. Performance.** One extra rename per write; row writes are per lifecycle step (tens per hour). Nil.

### R2 · Single-writer mutex on shared files
- **A.** `RowCommon.ps1:223-229` (`Update-DispatchedFile`), `:102-118` (`Assert-Lead` read-modify-write of `foreman-state.json`), `:119-127` (`Add/Clear-PublishOwed`), `:257-277` (`Test-Board` writes `boardTaskCount`), `:299-311` (`Set-BoardStatus` rewrites the 700 KB board), `Close-Row.ps1:86-90` (`actuals.json`), `Dispatch-Row.ps1:232-240` (`wave.json` from own rows only), `tools/Close-Row.ps1:61-82`. Two processes (two parallel tool calls, a Monitor's script beside a lead script) interleave read and write and the second write drops the first's entry.
- **B.** AIWorkHub's exclusive claim; standard named mutex. NOT Superharness's scheduler.
- **C.** `Invoke-WithLoopLock -Name <file> { read; validate; modify; atomic write }` around the WHOLE critical section, using `System.Threading.Mutex` named `Global\myloop-<sha1 of the file path>`; 30 s acquire timeout then throw naming the file; `AbandonedMutexException` is caught and treated as acquired (the previous holder died and R1 guarantees the file is whole). `wave.json` becomes a MERGE under the lock: keep every row still `dispatched`, add mine. Lock wait above 250 ms is recorded (`lock-wait` event with ms and file) so contention is measured, not guessed. Never held across Claude work, builds, tests or graders: the lock wraps a read-modify-write of one file, milliseconds.
- **D.** I2: concurrent writers cannot silently overwrite one another.
- **E.** N `pwsh` processes started with `Start-Process`, all blocking on one barrier file, then simultaneously `Update-DispatchedFile` with disjoint keys: every key lands, the file parses. Two simultaneous `Dispatch-Row` calls on disjoint rows: both rows in `dispatched.json` and both in `wave.json`.
- **F.** Only contention is between lead scripts, which today run serially. Measured by the `lock-wait` event; a P90 wait above 1 s is a defect.

### R3 · Row version (optimistic concurrency) — from Superharness
- **A.** `Write-Row` (`RowCommon.ps1:135`) writes the object the caller read minutes ago. `Collect-Row` runs 4-10 min of checks between its first `Write-Row` (`:111`) and its last (`:151`); a `Reconcile -MarkLost`, a second collector or a delayed verifier record in that window is overwritten without a trace.
- **B.** Superharness version CAS (`UPDATE ... WHERE version = ?`).
- **C.** Every row record carries `version` (absent = 0 for old records). `Write-Row` takes the row's mutex, re-reads the file, refuses with `StaleWriteException` and a `stale-write-refused` event if the on-disk `version` differs from the one the caller read, else increments and writes atomically. Callers that legitimately re-read (Collect after its checks) reload and re-apply. No script keeps a row object across a long operation without reloading it.
- **D.** I2 (row records): a stale process never overwrites newer state.
- **E.** Two writers read version N; A commits (N+1); B is refused, B's bytes never reach disk, the event is on record. Old records (version absent) still read, write and reconcile.
- **F.** One extra read per row write. Nil.

### R4 · claimEpoch (execution fencing) — from AIWorkHub
- **A.** `Collect-Row.ps1` accepts a `-Status` for the LAST attempt (`:82`) from anyone; a worker from attempt 1 returning after attempt 2 was dispatched stamps attempt 2. `myloop-wave.js` returns rows by key only. LOST + re-dispatch is exactly the window (4 LOST attempts on record).
- **B.** AIWorkHub epoch-fenced CAS: an expired lease cannot mutate after reclaim.
- **C.** A monotonic `nextEpoch` counter in `foreman-state.json` (under the R2 lock) is allocated at dispatch and stored as `attempts[n].claimEpoch`; `wave.json` rows and `<key>.prompt.md` carry it; the wave result carries it back; `Collect-Row -Epoch`, `-Verifier -Epoch`, `-Reject -Epoch`, `MarkLost -Epoch` refuse with `stale-epoch-refused` when the epoch is not the current attempt's. A hand collect without `-Epoch` is the lead's assertion and is logged as `epoch-unstated`. Designed with R7: a LOST attempt's epoch is retired, so its zombie result can never advance the row after re-dispatch.
- **D.** I3, I4: only the current epoch may advance the row; one attempt has one owner.
- **E.** Dispatch (epoch 41) → MarkLost → dispatch (epoch 42) → `Collect-Row -Epoch 41 -Status DONE` is refused and the record is byte-identical; `-Epoch 42` collects.
- **F.** Nil.

### R5 · Dispatch journal + ordering rule
- **A.** Five writes in `Dispatch-Row.ps1:176-240` with no intent record; the row record (the source of truth) is written FIRST, so a crash after it leaves a row that claims to be dispatched with no snapshot, no entry, no prompt (F1, F2).
- **B.** AIWorkHub's reservation-before-spawn + ledger replay; write-ahead intent (standard).
- **C.** `.loop/journal.jsonl`, append-only, `FileShare.Read`, flushed; a failed journal write THROWS (unlike `events.jsonl`, which is telemetry). Order, chosen because the row record is authoritative and everything else is reconstructible from record + intent:
  1. `dispatch-intent` {key, attempt, claimEpoch, expectVersion, ticketHash, graderHash, writeSet/after/exclusive/testProject, prevDispatchedEntry, at, lead}
  2. snapshot `_snap-<key>.json` (idempotent; means nothing until the record says dispatched)
  3. `dispatched.json` entry (R2 lock)
  4. row record → `dispatched` (R3 CAS) — **the commit point**
  5. prompt file + `wave.json` merge (re-derivable from the record)
  6. `dispatch-committed`
  Close gets the same shape: `close-intent` {key, version, minutes, residual, at} → row record `closed` (commit) → board close (`dispatched.json` → `started.json`) → `actuals.json` → board status → `close-committed`. Today's order (`Close-Row.ps1:81-105`) is reversed and is what strands F6.
- **D.** I5: a crash at any point of dispatch or close is reconstructible.
- **E.** Crash points after each numbered step; after restart `Reconcile` either rolls back (intent, no commit) or completes (commit, missing derivatives), and a second `Reconcile` changes nothing.
- **F.** One append per transition. Nil.

### R6 · Reconcile becomes a recovery engine (+ cycle report)
- **A.** `Reconcile-Rows.ps1` reports and changes nothing except `-MarkLost`. Shapes it sees today and leaves: record without entry (`:33`), entry without record (`:44-51`), no snapshot (found only at collect), torn files (dies), collected row whose entry is gone (F6, invisible).
- **B.** AIWorkHub reconciler thread (classify by identity: UNKNOWN defers, MISMATCH finalizes); Superharness has none worth borrowing.
- **C.** `Reconcile-Rows.ps1 -Repair` (also run by `Sync-Board` on every wake), deterministic cases, each emitting `reconcile-repair` with before/after:
  - A intent, no commit, record not dispatched → roll back: restore `prevDispatchedEntry`, quarantine the orphan snapshot.
  - B record dispatched, no `dispatched.json` entry → rebuild the entry from the intent.
  - C record collected/closed, bookkeeping incomplete (entry still live after close; started.json missing) → complete the close from `close-intent`.
  - D worker dead → R7.
  - E representations disagree → authority order: row record > journal > dispatched.json > started.json > board status. The lower one is rewritten from the higher; the board line is regenerated.
  - F stale epoch → refused (R4), reported.
  - Torn/quarantined record → reconstruct from the journal when every transition since the last committed one is journaled; otherwise `RECOVERY-REQUIRES-HUMAN <key>: <exact evidence>` in the OWED list. Never a guess.
  - `after` cycles among open tickets: `DEPENDENCY CYCLE A → B → C → A` as its own bucket in `Get-ReadySet` and in `Reconcile`; never auto-corrected.
- **D.** I7 (idempotent recovery), I11 (no silent ambiguity), I5.
- **E.** Each F-shape planted on a scratch copy; `Reconcile -Repair` twice; the second run reports zero repairs; the row then collects/closes normally. A planted cycle prints the cycle once, not three `waits on` lines.
- **F.** Reconcile already runs on every wake and reads every record; the repair pass adds a journal scan (KBs).

### R7 · Automatic LOST
- **A.** `Reconcile-Rows.ps1:35` prints advice; a human runs `-MarkLost`. A dead lead session (the only process that hosts workers) strands every dispatched row until someone notices (F3: 2 h in the verdict's injection; 17:34–22:0x on 09-14 in production).
- **B.** AIWorkHub's PID-identity ledger replay + lease reclaim; MyLoop's own `leadLockStaleMinutes`.
- **C.** Liveness is decided on the SESSION that owns the worker, because a `foreman-worker` is a subagent of the lead process and cannot outlive it. The lead lock gains `pid` (top-most claude/node ancestor, `Get-LeadIdentity` already walks it, `RowCommon.ps1:84-100`) beside `heartbeat`; each attempt records `dispatchedBy` {identity, pid}. Rule: attempt → LOST when `elapsed ≥ overdueFactor × estCalibrated` AND (`dispatchedBy.pid` is not running OR its heartbeat is older than `leadLockStaleMinutes`) OR the wave result says `lost: true`. A row whose lead is alive is reported OVERDUE and never auto-LOST. LOST retires the epoch (R4) so a late result is refused; the LOST attempt keeps `lostAt` and `lostWhy`. Re-dispatch is R9's; `Dispatch-Row` already waives the unchanged-ticket guard for LOST (`:73-80`).
- **D.** I6: a dead worker never permanently strands a row.
- **E.** Scratch: dispatch under a fake lead identity with a dead pid, backdate the attempt past 3×: `Reconcile -Repair` marks LOST with the reason; same row with the current live pid: OVERDUE only; the old epoch's collect is refused.
- **F.** One `Get-Process` per overdue row. Nil.

### R8 · Auto-collect on wave return
- **A.** SKILL step 10 is a per-row hand step; measured 237 min/day of finished workers waiting (median 2, P90 16). `myloop-wave.js` cannot run a script.
- **B.** AIWorkHub's crashed-supervisor-still-routes-to-review; standard "collect on completion".
- **C.** `Collect-Wave.ps1 -RootPath -ResultPath <wave result json>`: the lead writes the Workflow result to `.loop/wave/result-<stamp>.json` (one tool call) and runs one script that, per row, runs `Collect-Row -Json -Epoch -Status -Minutes -ReportedAt`, marks `lost: true` rows LOST (R7 path), runs `New-VerifierPrompt -Wave` for code/security rows, and prints the stage-`verify` Workflow args. It never closes; blind verification stays a separate stage; acceptance stays the lead's. `reported → collect-started` is measured by the existing `collect wait` column; target near zero. A `COLLECT DEFERRED` result (48.WAVE1) is re-collected on the next wake.
- **D.** I8 (idempotent collection — F4/F5 already are; kept and tested), I12 half.
- **E.** A result file with three rows (two reported, one null): both collected with their epochs, the third LOST, the verify args name only the code rows; running it twice changes no record.
- **F.** Collect runs (build + tests) are serial per row today; `Collect-Wave` keeps that order and the shared-build caveat of 48.WAVE1.

### R9 · Auto-dispatch of the legal accepted set
- **A.** SKILL steps 7-9 are the lead's by hand; 454 min/day with no worker running while a ready ticket waited (13 % of seat capacity in the replay). `Get-ReadySet` (`:1-30`) already computes the legal set and is the only authority.
- **B.** The idea only (Superharness `auto_dispatch`); NOT its readiness semantics (fail-open, four disagreeing implementations).
- **C.** The accepted marker becomes explicit and hash-bound: `Accept-Ticket.ps1 -Key` runs `Test-Ticket` (gate 1), requires a `lead-read` event for the key newer than the ticket file (gate 2 evidence, already logged by `Add-LoopEvent.ps1`), and writes `.loop/accepted/<key>.json` {ticketHash, graderHash, selfTestHash, at}; it also marks the row WAITING as `Mark-Started -WaitingOn` does today. `Sync-Board` gains an auto-dispatch step: not paused, seats free → `Get-ReadySet -Json` → keep READY rows whose accepted record's hashes still match the files → `Dispatch-Row -Keys` → print the wave. A ticket edited after acceptance is not accepted. Nothing bypasses a human gate (`afterGate` stays in `Get-ReadySet`). Scripts cannot call agents, so the wave launch stays the lead's first act on every wake (SKILL step 9).
- **D.** I12 (work conserving), I9, I10 (zero new false READY: the legal set is unchanged; the accepted filter only removes).
- **E.** Scratch board with three tickets: one accepted+legal, one legal+unaccepted, one accepted+edited-after: only the first is dispatched; paused loop dispatches nothing; a row behind an unapproved gate is never dispatched.
- **F.** `Get-ReadySet` reads every ticket on every wake (already does). Nil.

### R10 · Unified transition guard
- **A.** Each script decides its own accepted states: `Dispatch-Row.ps1:66`, `Collect-Row.ps1:57,78`, `Close-Row.ps1:15`, `Reconcile-Rows.ps1:14` (no check at all), `Collect -Verifier` (no state check). Script A allows what script B forbids.
- **B.** Superharness DB CHECK on status; standard state machine.
- **C.** One table in `scripts/lib/RowStates.ps1` and one function `Set-RowState -Row -To -By [-Epoch]` that enforces it, checks version (R3) and epoch (R4), journals the transition, and is the only writer of `state`. Matrix derived from the code (the spec's table was an example):

| From | To | Owner | Condition |
|---|---|---|---|
| (none) / rejected / lost / closed | dispatched | Dispatch-Row | ticket accepted + ReadySet-legal; new attempt, new epoch; closed→dispatched logged loudly |
| dispatched | collected | Collect-Row | current epoch, `-Status` present |
| collected | collected | Collect-Row | idempotent re-collect; verifier verdict recorded |
| dispatched | lost | Reconcile (-Repair / -MarkLost), Collect-Wave | dead owner + overdue, or wave result null |
| collected | rejected | Collect-Row -Reject | current epoch |
| collected | closed | Close-Row | checks pass or `-Override`, verifier verdict exists (code/security), Residual named |
| (none) | approved | Approve-Gate | gate rows only |
Anything else → `transition-refused` event + throw. The same table is printed in SKILL.md.
- **D.** I4, I9; no script can move a row where the matrix forbids.
- **E.** Every forbidden pair attempted on a scratch row is refused and the record is unchanged; every allowed pair succeeds; the suite enumerates the matrix rather than a hand-picked few.
- **F.** Nil.

### R11 · Failure-injection + concurrency chaos suite
- **A.** `tests/Test-MyFableNext.ps1` (18 cases) has no crash or concurrency case.
- **B.** AIWorkHub's chaos tests (orphaned child terminated; expired lease cannot mutate) and Superharness's DB-concurrency/garbage-file suite, adapted to files.
- **C.** `Invoke-CrashPoint '<label>'` in `RowCommon.ps1`: a no-op unless `MYLOOP_CRASH_AT=<label>`, then `exit 137`. Labels at every point in spec §16. `tests/Test-LoopChaos.ps1 -Scripts <folder>` runs each label on a fresh scratch copy, then `Reconcile -Repair` twice, and asserts: no key lost, no key duplicated, every JSON parses, ReadySet identical to the pre-crash legal set, no exclusive double-owned, closed work not re-run, incomplete attempts resumed or LOST, ambiguity surfaced. Concurrency: N processes on a start barrier running Dispatch/Collect/Reconcile/Sync-Board/Close mixes; stale collector, stale verifier, old worker after re-dispatch, close racing reconcile → one legal end state. Run against the pre-hardening scripts (`scripts-stage-<stamp>` kept as the BEFORE baseline) the suite must FAIL on the shapes each row fixes; against the new scripts it must be green.
- **D.** Proof of I1-I12.
- **E.** The suite is the test.
- **F.** Wall-clock of the suite only.

### 48.WAVE1 · Wave-aware collect (already filed, unticketed)
- **A.** `checks/code.ps1:11-20` builds and tests the shared tree while a wave-mate's edit is half-landed (52.S0.4y on 52.S0.8); `Get-RowChanges` counts an appendOnly file another row's close just merged as a violation (52.S0.4v). 19 of 42 override closes were attribution-class.
- **C.** `Collect-Row` returns `COLLECT DEFERRED — blocked by active wave mate <key>: shared build` when another `dispatched` row holds a code write set in the same solution, leaves the row `dispatched`, and `Collect-Wave` retries on the next wake; the scope gate exempts a declared appendOnly path changed by another row's close (the closed row's `appended` record names it).
- **D.** No misattributed FAIL; I8 kept.
- **E.** A staged two-row wave: the innocent row's collect says DEFERRED and names the mate, never FAIL; after the mate closes, the collect passes.

## 2 · Row decomposition (all class `code`, `exclusive: loop-scripts`, seat opus, write set = the skill folder + `.loop/tools/Close-Row.ps1` where named)

| Key | Row | after | est |
|---|---|---|---|
| 48.R1 | Atomic writes + quarantine (`Write-Json`, `Read-Json`, `Write-LoopJson`, `tools/Close-Row.ps1`, `Write-Schedule.ps1`) | — | 45 |
| 48.R2 | Shared-state mutex + `wave.json` merge + lock-wait event | 48.R1 | 45 |
| 48.R3 | Row `version` CAS in `Write-Row` | 48.R2 | 45 |
| 48.R4 | `claimEpoch` on attempts; `-Epoch` on Collect/Reject/MarkLost/Verifier; wave carries it | 48.R3 | 60 |
| 48.R5 | Dispatch + close journal and ordering rule | 48.R4 | 60 |
| 48.R6 | Reconcile `-Repair` (cases A-F, torn reconstruction, RECOVERY-REQUIRES-HUMAN) + cycle report | 48.R5 | 90 |
| 48.R7 | Automatic LOST on dead owner + overdue; `pid` in the lead lock | 48.R6 | 45 |
| 48.R8 | `Collect-Wave.ps1` auto-collect + verify-stage args; SKILL step 10 | 48.R4 | 60 |
| 48.WAVE1 | Wave-aware collect: DEFERRED, appendOnly-by-close exemption | 48.R8 | 60 |
| 48.R9 | `Accept-Ticket.ps1` hash-bound marker; `Sync-Board` auto-dispatch | 48.R7 | 60 |
| 48.R10 | `RowStates.ps1` matrix + `Set-RowState` in every script; SKILL table; Archify state diagram | 48.R9 | 60 |
| 48.R11 | `Test-LoopChaos.ps1` crash + concurrency suite; BEFORE-baseline run recorded | 48.R10, 48.WAVE1 | 90 |

They share `RowCommon.ps1` and `tests/Test-MyFableNext.ps1`, so they run serially by write-set overlap whatever the order; the
`after` edges make the reason explicit. Each row: staging-copy workflow (48.CGL1 TASK 1), a case in `Test-MyFableNext.ps1`
that fails on the pre-edit staging copy and passes on the new scripts, a SKILL.md paragraph, and a blind verifier.

## 3 · Invariant → proof

| Inv | Proven by |
|---|---|
| I1 atomicity | R1 self-test + R11 `write-before-move` |
| I2 no lost update | R2 barrier test + R3 two-writer test |
| I3 epoch fencing | R4 test; R11 old-worker-after-redispatch |
| I4 single claim | R10 matrix + R4 |
| I5 replayable dispatch | R5 + R6 crash points |
| I6 dead attempt handled | R7 |
| I7 idempotent recovery | R6 (twice = same) in every R11 case |
| I8 idempotent collection | existing F4/F5 kept; R8 twice |
| I9 correct dependency release | Get-ReadySet unchanged; R11 asserts ReadySet identical pre/post crash |
| I10 zero new false READY | R9 only filters; shadow replay re-run after R9 |
| I11 no silent ambiguity | R6 RECOVERY-REQUIRES-HUMAN |
| I12 work conserving | R8 + R9; throughput `no worker while ready ticket waited` |

## 4 · Metrics baseline (2026-09-16, 24 h window and record census)

| Metric | Before | Source |
|---|---|---|
| Stranded rows (needed a hand `-MarkLost`) | 4 attempts / 88 rows, 1 without `lostAt` | row records |
| Torn state files observed | 0 (17 in-place write sites, 0 atomic) | code census |
| LOST detection latency | manual; 2 h in injection, ~4.5 h on 09-14 | verdict F3, memory |
| Worker DONE → collect | 237 min/day waiting; median 2, P90 16 | throughput.md |
| READY → dispatch | 454 min/day no worker while a ready ticket waited; queue median 31 | throughput.md |
| Legal seat utilisation | 0.62 of 7 (time-weighted); 0.85 legal-seats-filled at dispatch moments | throughput.md, verdict |
| Mutex wait / version conflicts / stale-epoch refusals / reconcile repairs | not instrumented (0 by absence) | — |
| Manual recovery actions | every LOST, F1, F6 | verdict |
| Override closes | 42 of 84 closed; 19 attribution-class | records, verdict |

## 5 · Risks and decisions

- **The loop edits itself while running.** Every collect dot-sources `RowCommon.ps1`. The staging-copy rule (48.CGL1) lands whole
  files; `exclusive: loop-scripts` serialises these rows; the lead runs each with no other row in flight where the write set is
  `RowCommon.ps1`. 48.CGL1 did exactly this and the loop survived its own rewrite.
- **Windows facts relied on.** `File.Move(overwrite)` is atomic on NTFS for same-volume paths (`.loop` is on `C:`); the scripts
  live on `Q:` (SMB) but are only read. A named `Global\` mutex is machine-wide; `.loop` on SMB would void it — not our case.
- **Liveness by lead pid.** A resumed session may reuse the session id; the pid does not. Both are checked; the conservative
  answer (alive) wins, so the worst case is an OVERDUE report, never a false LOST.
- **The accepted marker is new state.** It is the smallest thing that makes "lead accepted THIS ticket text" machine-readable
  without touching the two human gates.
- **Not doing.** No SQLite. No per-worktree isolation. No scheduler change: `Get-ReadySet` stays the only authority.
