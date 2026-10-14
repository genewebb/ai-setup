---
name: reference_myloop_orphan_recovery_and_script_gaps
description: "How to recover a MyLoop wave orphaned by a dead lead session, plus the three MyLoop script defects that recovery exposed and fixed (2026-09-14)"
metadata: 
  node_type: memory
  type: reference
  originSessionId: 979a1ac8-399e-4a30-b509-754d9ebacca2
  modified: 2026-09-14T22:14:32.183Z
---

A lead session died mid-wave (2026-09-14 ~17:34), leaving three rows `dispatched` with no worker report
and one `collected` and unread. `Sync-Board.ps1` correctly refused to write from the second session
("ANOTHER session; this one is read-only"); `Claim-Lead.ps1 -Take` is the only way past it, and it must
not be used until a human confirms the other terminal is actually gone — a heartbeat under ~10 minutes
old plus fresh wave output means it is probably alive.

**Judge an orphan on its grader, never on the missing report.** Run each row's grader and list the write
set with DATES (`ls --time-style=+%m-%d_%H:%M`; a bare `%H:%M` on the NAS-mounted `Q:` makes files from
days ago look minutes old). Three outcomes:
- grader GREEN and write set on disk: the work landed. Collect it; the blind verifier is unaffected
  because `New-VerifierPrompt.ps1` gives it the ticket and the diff, never the worker's reasoning.
  Say plainly in `_decisions.md` that the recorded status is the lead's reading of the evidence, not
  something a worker said.
- grader RED but most clauses green: `Reconcile-Rows.ps1 -MarkLost <key>`, then append an **ATTEMPT N**
  section to the ticket naming exactly what is already on disk and which clauses remain. Worth doing:
  52.P1.8c finished in 9 minutes instead of redrawing nine screens.
- grader RED and nothing written: mark LOST and re-dispatch unchanged.

**Three script defects this exposed, all fixed in `Q:\Work\Work\03 Shared\work-ai\skills\myloop\scripts\`**
(`myloop` and `myfable-foreman` are symlinks to that one directory, so one edit covers both; write it
through `Write-VaultFile.ps1`, never directly):

1. `Publish-Done.ps1` elected the live schedule artifact by **highest `lastSeenVersion`**. Version
   counters are per page and independent, so when the account flips back to a page with a lower count it
   stamps the version onto the page this account cannot open — and each wrong stamp raises that entry's
   counter and re-elects it. Now takes `-Url`, falls back to an explicit `live` flag, warns with neither.
   **Always pass `-Url`.** See [[reference_claude_account_switching]].
2. `Dispatch-Row.ps1` refused every re-dispatch whose ticket and grader were unchanged. Right for a
   REJECTED attempt (judged, found wanting); wrong for a LOST one (never judged, may have produced
   nothing). Now exempt when the previous attempt's status is `LOST`.
3. `Close-Row.ps1` hard-threw for a code/security row without a verifier PASS, which made
   [[feedback_loop_two_strike_rule]] impossible to apply to those classes — closing on what passes IS a
   close over a recorded FAIL. Now a verdict must EXIST, but a FAIL can be closed over with `-Override`
   plus `-Residual <key>`; the FAIL stays on the record beside the reason, never replaced by it. This
   matches the skill's own principle 3: acceptance is the lead's alone, a verdict is evidence.

**Still open:** the `mockup` class check has no exemption for another in-flight row's declared files, so
a concurrent code/security row writing the repo reads as a `repos-clean` violation on the mockup row.
The `code` class check has that exemption. 52.S0.1b was closed with `-Override` because of it; it will
misfire again on any concurrent mockup + code pair.

Related: [[project_myfable_foreman]], [[project_myloop_wave_upgrade]], [[reference_started_state_was_transient]].
