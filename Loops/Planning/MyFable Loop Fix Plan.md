---
title: MyFable Loop Fix Plan
created: 2026-09-13
status: built and tested; cut over to `myloop` 2026-09-13 20:2x
owner: Gene
applies-to: work-ai/skills/myloop (formerly myfable-foreman)
related:
  - "[[Worker Runner Plan - herdr]]"
  - "[[MyFable-Foreman-Field-Guide.html]]"
---

# MyFable Loop Fix Plan

## In one paragraph

MyFable worked: rows closed, the blind verifier caught real bugs, the scripts removed most of the clerical work. The review of 2026-09-13 found places where the loop could **say green when it wasn't**, **leave a rule to memory instead of a script**, or **time things against estimates that were too high**. Running it the same day found more: two sessions writing the same files, a pause that had to be done by hand, control bytes reaching the board, and prompts the loop could have answered itself. All of it is fixed in `myloop`: a staging copy of the skill, a test per fix written first, swapped in at a quiet moment.

**Two requirements shape the result:**
- **The loop never prompts.** A decision with a recommended option is taken and logged. It stops only at a human gate, on BLOCKED, or when paused.
- **The running list is always current.** Every state change regenerates the schedule and the status pages; a heartbeat regenerates them again so elapsed times stay honest; what still has to be published is recorded and reported, never remembered.

## The fixes

| # | Fix | Why | How | Test |
|---|---|---|---|---|
| 01 | Re-check earlier rows at collect | a row that moves or renames something turned earlier graders red for days without anyone running them | closed rows whose write set or grader names a changed file have their graders re-run (static clauses); a FAIL blocks close; a ticket's `supersedes: [key:CLAUSE]` list marks reds made on purpose | fix 01 |
| 02 | Constraint judged against a per-row snapshot | the shared baseline went stale, and `git status` forgets a commit made mid-row | `Dispatch-Row.ps1` hashes the tree into `rows\_snap-<key>.json`; collect compares against it; files of other in-flight rows, or of rows closed since, are named and not counted | fix 02 |
| 03 | Calibrated estimates drive the alarms | overdue fired at ~10× real time; the monitor gave up at a fixed 2 h | calibrated = est × median(actual ÷ est) over closed rows of the class (raw until 3 rows); monitor polls for 3× that (floor 30); reconcile flags at 3× | fix 03 |
| 04 | Collect needs the worker's status | the monitor's green can arrive while the worker is still testing | `-Status` is required on the normal form | fix 04 |
| 05 | No re-dispatch on an unchanged ticket | the same input gives the same result | ticket and grader hashes per attempt; both unchanged = refused | fix 05 |
| 06 | Gate refuses without the batch verifier | a gate could be approved with the batch unverified | `Collect-Row.ps1 -Batch` writes the batch record; `Approve-Gate.ps1` refuses without a PASS covering every closed row | fix 06 |
| 07 | Append-only shared files | two rows that both add a census line could not run together | ticket `appendOnly:`; exempt from the overlap test; workers write `.loop\append\<key>\<file>.lines`; close merges in key order | fix 07 |
| 08 | Per-repo config | the scripts hard-coded one programme | `.loop\foreman.json`, every value optional; loop helpers vendored under `scripts\lib` | smoke |
| 09 | Docs match reality | the record said "fable" whatever ran | lead, workers and verifier are opus (config); the verifier record carries `model`; the state list matches the scripts | fix 14 |
| 10 | Minutes worked out, not typed | hand-typed minutes on every close | default = Σ(collectedAt − at) over attempts; `minutesBasis` recorded | fix 10 |
| 11 | One lead per repo | two sessions overwrote each other's board and design edits | lead lock in `foreman-state.json`; every writing script refuses when another live session holds it; `Claim-Lead.ps1 -Take` | fix 11 |
| 12 | Pause is a state | pausing meant cancelling wake-ups by hand | `Set-Pause.ps1 -On/-Off`; dispatch and close refuse while paused; `/myloop` honours it after a restart | fix 12 |
| 13 | Board guard | an ESC byte reached the board; a malformed row vanishes silently | before every regeneration: no control bytes, parses, no duplicate keys, the row count never drops unless expected | fix 13 |
| 14 | Scripted verifier prompt | retyped by hand every row, from `git status` | `New-VerifierPrompt.ps1 -Key` from the record: ticket, files changed since the snapshot, verdict sheet, model | fix 14 |
| 15 | Test-floor drift | a floor that waited in a ticket went stale | dispatch warns when `testFloor` is below the last closed row's passed count | fix 15 |
| 16 | The running list stays current | the pages went stale between closes | every state change regenerates; `Sync-Board.ps1` on every wake; `publishOwed` recorded and cleared by `Publish-Done.ps1` | smoke |
| 17 | No prompts | the loop asked what it could answer | no compact checkpoint; decisions taken and logged; stops only at gate / BLOCKED / pause | SKILL.md |
| 18 | Monitor polls static clauses | a full grader every minute fought the worker's own build | `-StaticOnly` when the grader declares it | fix 03 |
| 19 | Vault writes through the API | Obsidian holds files open over SMB and its index misses direct writes | `Write-VaultFile.ps1`; direct writes only with `-AllowDirect` | manual |

## Ground rules (kept)

1. Built in a copy (`myfable-foreman-next`), cut over by rename at a quiet moment.
2. Test first: `tests/Test-MyFableNext.ps1` runs every script against a scratch copy of `.loop` with status-page writes switched off. 16 tests; all green before cut-over.
3. Old records keep working: every new field is read with a "missing means default" helper; the real row records are part of the test data.
4. Never commit.
5. `CHANGES.md` in the skill lists every change and why, so a future upstream merge can re-apply them.

## Cut-over (done)

- The live folder renamed to `myfable-foreman-prev-2026-09-13`; the new one is `myloop`.
- `/myloop` is the command: no arguments = resume from `<repo>\.loop\`; `pause`, `resume`, `status`, `next <keys>`. `/myfable` redirects to it.
- The row in flight at cut-over (52.S0.2) got its dispatch snapshot rebuilt from the commit before its attempt, so the new checks can collect it.

**Rollback:** stop the session, rename the folders back, resume. Records written by the new scripts only add fields.

## Open

- herdr / background runner: if it goes ahead, fixes 04, 10 and 14 already keep the report and the timing in the record, which is what a runner needs.
- A stronger verifier model for security rows only (`verifierModelByClass`): the knob exists, default opus.
