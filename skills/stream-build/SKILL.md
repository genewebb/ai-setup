---
name: stream-build
description: v0.10. Stream kit skill 3 of 5. Each cycle first takes the oldest actionable item from its inbox (.streams\inbox\stream-build.md). It runs unattended and never prompts; every decision a ticket leaves open is auto-accepted (the builder takes its own recommendation, logs it and keeps building) because the owner adjusts at manual testing. It claims ticketed tasks from .streams\tasks.json and builds each one in its own detached git worktree, with no branches and no commits. It proves RED first in that worktree, chooses and writes one test per acceptance clause plus the existing tests its change can break, records them as a runnable check, and hands off a write-set-limited patch with that record; a blind verifier subagent tries to refute it before the task is marked built. Use for /stream-build (run under /loop), /stream-build once, /stream-build status.
---

# stream-build

Skill 3 of the stream kit. It turns `ticketed` tasks into `built` tasks: a verified patch that the integrator applies to
the main tree. It never prompts, never commits, never branches, and never touches the main tree.

## Auto-accept (owner standing rule, 2026-09-27)

The owner auto-approves the builder's recommendations and adjusts anything at manual testing, so the builder keeps
building instead of stopping for a choice. Whenever the ticket leaves something open, the builder picks the option it
would recommend, records it, and carries on:

- **An unstated decision or an ambiguous clause** (naming, a message wording, which of two readings, an edge case the
  ticket did not cover, a follow-up the ticket asks to file): take the recommended reading. Record one line with
  `Update-Task.ps1 -Note "decision (auto-accepted): <what> -- <why>"` and add it to the verdict request (step 7) so the
  verifier grades against it.
- **The change needs a file outside the write set**: widen the write set with
  `Update-Task.ps1 -Role build -AddWriteSet <file[,file]> -Note "<why>"`. It writes the task and a `decisions.md` line.
  Exit 7 (`WRITESET-OVERLAP`) means another open task owns that file; only then is the task marked `blocked` with
  "write set needs <file> (owned by <task>)".
- **A dependency already met the ticket** (every clause test passes before any implementation in step 4b): still
  `blocked` with "already met" — there is nothing to build — and the builder claims the next task at once.
- **A verifier finding that is advice, not a defect** (a style note, a follow-up, a cosmetic point): accept the
  verifier's recommendation if it is inside the write set and cheap, otherwise log it as a follow-up; neither blocks
  `built`.

What auto-accept does **not** cover, because the builder cannot fix it by choosing: a grader or ticket that is wrong
(it still goes back to `planned` with the reason), a second verifier FAIL, and anything destructive (removing a
worktree, deleting data outside a test's own temp folder), which stays the owner's call.

## Start

```
/loop /stream-build repo: {SpeedyRepo}
```

**Fresh context (preferred; owner ruling 2026-10-04).** Instead of `/loop`, run this role from a plain terminal with
`pwsh -NoProfile -File "{ClaudeHome}\skills\stream-kit\scripts\Start-StreamRunner.ps1" -Repo {SpeedyRepo} -Role build`.
The runner starts a new headless Claude session for every task it builds, so nothing carries over from the last one's
context. Each runner session gets its session id and the headless rules in its system prompt:
- run one cycle;
- never call ScheduleWakeup;
- never end the turn while its own work is still running;
- start anything that must outlive the session (an integrator suite, a drain) detached with `Start-Process`.

The `/loop` form above still works.
The runner launches only when there is something to take: an actionable inbox item, or a row the claim would offer.
Otherwise it sleeps 30 minutes at no token cost.

**Watch it live (owner ruling 2026-10-04).** Add `-Live` to the runner line to run each unit as an interactive session in the
runner's own terminal, with Remote Control on (claude.ai/code and the Claude app list it under its session id), or
`-Stream` for a live text feed of a `-p` session. Under `-Live` the cycle ends with one call to
`mcp__stream-unit__unit_done` (outcome `built`, `ticketed`, `planned`, `integrated`, `done`, `idle`, `blocked` or
`failed`, and a one-line note), made only after every result of the cycle is written under `.streams\`; the session
then exits by itself. The outcome is the state the cycle left the row in: a verifier FAIL that sends the row back is
`ticketed`, a row parked on an owner or planner question is `blocked`. `failed` is for a cycle that could not finish
(a script or tool broke, the work could not be saved). No reported outcome backs the runner off; only a non-zero exit,
a CLI error with no outcome, a rate limit, or `NO-RESULT` / `TIMEOUT` with no result does (kit item
IN-20261010153049-6849). A session without that tool (a `/loop` session, `-p`) ends the cycle as before.

**Pre-staged units (2026-10-06, prestage-runner-design).** The runner does steps 0 to 3b and 4a itself, in PowerShell,
before it starts you: it takes the oldest actionable inbox item in your session's name OR claims the next row with
`Claim-Task.ps1` (the gate's own selector), lays the worktree (`New-TaskWorktree.ps1`), proves the author grader RED
on the fresh tree (`Invoke-Grader.ps1 -Only grader -Label red -ExpectRed`; a row that is not red goes back to `planned`
with the evidence and you are never started), restores a kept patch (`Restore-TaskPatch.ps1`) and grades a restored one
(`-Label wt`). It writes a PACKET under `.streams\units\<session>\`: `task.json` (the row) and `unit.md` (the held
item, the row summary and artifact paths, the worktree path, the RED and restore results, and the lessons). Your
command then ends with `packet: <path to unit.md>` and your rules name it. **Read `unit.md` first and skip steps 0 to
3b and 4a**: the row is claimed by your session and `building`, the worktree is laid, RED is on record. Continue at 4b
(or where the packet's restore result says). One item OR one row per unit; do not take or claim anything else, and end
the unit when that work is done - the runner starts the next unit at once. When a unit dies mid-build, the runner
exports its worktree to the row's patch before it releases the claim, so the next build restores it. A `/loop` session
or a plain `once` with no `packet:` does those steps itself as before.

**Models are configuration.** `.streams\config.json` (written by the runner with empty fields the first time) sets
per role, or for every role, the unit's `model`, its `subagentModel` (the verifier), `effort` and `promptCacheTtl`;
the runner reads it before every unit, so an edit takes effect at the next unit. When your rules name a subagent
model, put it on every `Agent` call, whatever step 7 says.

**Lessons.** A runner session starts empty, so it reads `.streams\lessons\build.md` before it claims or takes work
(in a pre-staged unit the packet holds them): one line per
lesson from earlier units of this role. Add one only for something a later unit needs and cannot read from `.streams\`:
`pwsh -NoProfile -File "{ClaudeHome}\skills\stream-kit\scripts\Add-Lesson.ps1" -Repo {SpeedyRepo} -Role build -Session <id> -Task <id> -Text "<one line>"`.
Never ticket detail, never a secret.

Several builder sessions can run at once. Each works in its own worktree, so there are no bin-folder locks between
builders. `/stream-build once` builds one task and stops.

## One cycle

FOCUS (2026-10-05, priority-focus-design 3.1; owner-set since 2026-10-06): you are offered rows from the FOCUS SET only -
the rows of the focus group(s), plus the rows their work depends on (`lib\Streams.ps1 Get-FocusSet`). The owner names
the focus group(s) in `.streams\config.json` as `"focus": { "groups": ["G4"] }` (one or more); an empty list means the
first unclosed group in board order. A claim that reads NONE means the focus has nothing for you now; never look for
work in another group, and never file an author or build inbox item about a row outside the focus
(`Send-InboxItem.ps1` refuses it: NOT-FOCUS). `Integrate-Patch.ps1` prints NOT-FOCUS for a built row outside the focus
and leaves it built. Builders never spill outside the focus; only authors do (owner ruling 2026-10-12).

SPILL TICKET (owner ruling 2026-10-12): a row with a `spill` field was ticketed by an author before its group was focus,
against main at `spill.base`. Before coding it, run `git -C <repo> diff --name-only <spill.base> HEAD -- <write set>`.
Any file listed (the claim also warns `STALE-TICKET <id>`, and the board flags it) means the ticket may cite code that
has moved: re-read the ticket and grader against the current files. When they no longer fit, release the row with a
note and file a `stream-author` item to refresh it; never build against a ticket you know is wrong.

PRE-STAGED UNIT: when your command carries `packet:`, steps 0 to 3b and 4a are DONE by the runner. Read the packet's
`unit.md`, then continue at 4b (a claimed row; the packet says whether a kept patch was applied and how it graded) or
do the held item's work (an item). Never run them again.
0. **Inbox.** List `<repo>\.streams\inbox\stream-build.md` (its contract is at the top of the file) with
   `Get-InboxItems.ps1 -Skill stream-build -Open`. Take the **oldest open item this skill can act on**, before claiming
   anything in step 2:
   - Take it with `Set-InboxItem.ps1 -Status taken`. Exit 8 (`ALREADY`) means another builder has it: skip it. Do the
     work, then close it with `Set-InboxItem.ps1 -Status done` or `declined` and the result or reason.
   - **Allowed actions, and only these:**
     - **Resume or rebuild a named task.** Act only when this session holds that task's claim, or the task is
       claimable under step 2's rules (for a resume, a stale claim counts as claimable). Then run the normal cycle
       (steps 3 to 8) on it. `Claim-Task.ps1 -Task <id>` claims that row when it passes the same gates as the sort,
       so a named row can be built under its item; a refusal prints `REFUSED-TASK <id> : <gate>` with exit 2, and
       then leave the item `open` and build what a plain claim returns.
     - **Reuse a task's kept patch** (`artifacts.patch`, or the file under `.streams\patches\`) as the start of a
       rebuild, then grade and verify as in steps 4 to 7.
     - **Check a built-but-not-integrated patch** for a builder-side bug. Apply it to a fresh detached worktree, run
       its grader there, and read the diff. Save the log to `.streams\logs\` and the finding to `.streams\verdicts\`.
       Append `done` with the result. A confirmed defect needs the integrator to hold the patch back, so it is also
       `forwarded` to `stream-integrate`'s inbox with the evidence path.
   - It never touches the main tree. An item that asks for anything outside the write rules (below) is forwarded with
     `Set-InboxItem.ps1 -Status forwarded -ForwardTo <skill>`, which writes both lines.
   - No open item it can act on: go straight to step 1.
1. **Identity.** Use a session id `build-<yyyyMMddHHmm>-<4 hex>`, kept for the session.
2. **Claim** (under the `tasks.json` lock). Take the first task that meets all of these:
   - its state is `ticketed`;
   - its kind is `code` or `docs` (`mockup` is below; `integration` and `gate` belong to other skills);
   - it has no live claim;
   - every `dependsOn` task is `built`, `integrated` or `done`.

   Critical-path tasks come first, then the oldest. Set `claim = {session, role: "build", at, beat}` and state
   `building`.
3. **Worktree.** Create `{WorktreesRoot}\<repo name>\<task>` with `git -C <repo> worktree add --detach <path> HEAD`.
   Then lay down the base, in this order:
   - the main tree's uncommitted diff (`git -C <repo> diff HEAD --binary`, applied in the worktree);
   - the main tree's untracked, non-ignored files (`git ls-files --others --exclude-standard`), copied across;
   - the patch of every dependency that is `built` but not yet `integrated`, in dependency order.

   Stage the whole base in the worktree's own index (`git add -A`). The builder's change is then exactly what is left
   unstaged. Record the base fingerprint (the hash of the main diff, the untracked list and the dependency patch hashes)
   on the task.

   **3b. Kept patch.** A task that bounced back (rebase, grader red on main, grader-suspect) keeps `artifacts.patch`.
   Run `Restore-TaskPatch.ps1 -Task <t> -Worktree <path>` before anything else:
   When the row has no `artifacts.red` yet and has an author grader, run step 4a on the fresh worktree BEFORE the
   restore, because step 4a needs a tree with no edit in it.
   - `APPLIED`: the earlier work is now this build's change. Its RED is already on record (`artifacts.red`). Run
     `Invoke-Grader.ps1 -Label wt`: PASS goes straight to step 6 and then verify; FAIL continues at step 5, building
     on top of it. A kept patch whose row has no `artifacts.check` gets one written now (step 4b, minus the RED run,
     which the kept patch makes impossible; say so in the test record).
   - `CONFLICT` or `NO-PRIOR`: nothing was written; build as usual from step 4.
4. **RED, first, in the worktree** (owner rulings 2026-10-02, kit items IN-20261002160453-ce2a and
   IN-20261002160643-741d). The author no longer proves RED: that ran on the main tree under
   `.streams\main-grader.lock` and queued every release behind any long main-tree run. Your worktree is private, so it
   needs no lock.
   - **4a. The author's grader, before ANY edit** (only when the row has `artifacts.grader`):
     `Invoke-Grader.ps1 -Task <t> -Root <worktree> -Only grader -Label red -ExpectRed -BeatSession <id> -BeatTask <t>`.
     Every clause must fail for the ticket's stated reason. If a clause passes, or fails for another reason (a build
     error elsewhere, a different message), make NO edit: send the row back with
     `Update-Task.ps1 -Role build -To planned -Release -Artifacts @{red='.streams\logs\<t>.grader.red.txt'} -Note "builder RED refused (origin: builder RED, IN-20261002160453-ce2a): <clause>: <what the output shows> - evidence .streams\logs\<t>.grader.red.txt"`,
     one history note naming the clauses, then claim the next task.
   - **4b. Clause tests, RED before implementing.** Write or select ONE test per acceptance clause (A1, A2, ...), and
     write nothing else yet. A new test file outside the write set is added with `-AddWriteSet` (Auto-accept). Then
     write `.streams\checks\<t>.ps1`, the row's check. Its contract is the grader contract (`param([string]$Root)`,
     one `PASS <id>` or `FAIL <id>: <reason>` line per entry, exit 0 only when all pass, runs in any tree, never a
     whole suite, PORTABLE under `Test-GraderPortability.ps1`). It runs:
     - one entry per clause, `A<n>`, its test by filter;
     - one entry per IMPACT test, `I<n>`: every EXISTING test that covers the files you will change (their own test
       classes, tests of the callers, tests that pin the same strings or types). Choose them now, from the write set
       and the code, and say why each was chosen.
     Record it with `Update-Task.ps1 -Artifacts @{check='.streams\checks\<t>.ps1'}`, then run
     `Invoke-Grader.ps1 -Only check -Label red-check -ExpectRed` with `-BeatSession -BeatTask`. Every `A` entry must
     fail for its clause's reason; `I` entries pass (they guard existing behaviour). A clause test that already passes
     means the clause is met or the test is wrong: fix the test, or mark the row `blocked` "already met" when every
     clause is.
   - Record the RED evidence: `Update-Task.ps1 -Artifacts @{red='.streams\logs\<t>.grader.red.txt,.streams\logs\<t>.grader.red-check.txt'}`.
     Each log ends with its `GRADER sha`, so the verifier and the integrator see what was red and under which scripts.
5. **Build.** Implement the ticket inside the write set. Run `Invoke-Grader.ps1 -Root <worktree> -Label wt`, which
   runs the check and, when the row has one, the author's grader, until it PASSES: every clause test and every impact
   test green, in the worktree only. Do not run whole suites and do not run other tasks' graders; the suites run once
   at group close. If the build shows an impact you did not foresee, add that test to the check (an `I` entry) and
   say why. Never weaken, skip or delete an existing test to get green. Every open choice is auto-accepted (see
   Auto-accept) and noted on the task; the builder never waits on one.
6. **Patch.** In the worktree, run `git add -N .` so new files show, then `git diff --name-only`:
   - A file outside the write set is either reverted (it was incidental) or, when the change truly needs it, added to
     the write set with `-AddWriteSet` (Auto-accept). Only a `WRITESET-OVERLAP` refusal marks the task `blocked`.
   - `git diff --binary` is saved to `.streams\patches\<task>.patch`.
   - The last run before export must be `Invoke-Grader.ps1 -Label wt` on the final worktree content: the integrator
     reads that log (its clause results and `GRADER sha`) to tell a check defect from a code defect when main goes red.
   - Write the TEST RECORD to `.streams\verdicts\<task>.tests.md` and set `artifacts.testRecord`:
     - the clause-to-test map (A-id, test name and filter, the REQ/AC it proves);
     - the impact list (I-id, test, and the reason it was chosen: which changed file or caller it covers);
     - the RED output (the `red` and `red-check` logs, quoted per entry) and the GREEN output (the `wt` log), each with
       its `GRADER sha`.
7. **Verify.** A fresh blind subagent (`foreman-verifier`, launched with `model: "sonnet"` on the Agent call: owner
   ruling 2026-10-03, cost review; a subagent model named in your runner rules from `.streams\config.json` wins) gets
   the requirement clauses, the ticket, the test record,
   the check, the author's grader when there is one, and the patch, and never the builder's reasoning. It also gets
   the list of auto-accepted decisions and widenings (as facts to grade against, not as reasoning). It re-runs
   `Invoke-Grader.ps1` in the worktree and is told to REFUTE:
   - an acceptance clause with no test, or a test that does not prove its clause;
   - a test a wrong change could pass;
   - an existing test that was weakened, skipped or deleted;
   - an impact list that misses an obvious caller or test of a changed file;
   - a RED that did not fail for the clause's stated reason.
   Its verdict goes to `.streams\verdicts\<task>.md`, auto-accepted decisions listed in it.
   - **Give the verifier its paths in forward-slash form, and tell it to quote every path in the Bash tool.** The
     verifier's Bash tool is Git Bash, run in the repo root, where an unquoted backslash is an escape. On 2026-10-04 a
     G3.T057 verifier ran `pwsh ... > D:\tmp\claude\...\scratchpad\verify-run.txt` unquoted: bash stripped every <!-- history -->
     backslash, the drive colon became U+F03A, and the grader output landed in the main tree's root as
     `D<U+F03A>tmpclaude...verify-run.txt` (kit item IN-20261004224625-9f42). Put this line in the verifier prompt:
     "In Bash, write Windows paths with forward slashes (`D:/tmp/...`) and quote them; never redirect to a backslash <!-- example-path -->
     path. Write scratch output only under `<scratchpad, forward slashes>`."
   - **THE BUILDER writes that file, not the verifier.** `foreman-verifier` holds Read, Glob, Grep and Bash only and
     its own contract forbids writes, so it returns the verdict text and the builder persists it verbatim. The file
     opens with one line saying the text below is the verifier's and that the builder only wrote it down, so the
     provenance survives for whoever reads it later. Never edit, shorten or answer that text: put the builder's own
     note under a separate heading if something needs saying. A read-only auditor is the point - an agent that can
     write into the tree it is auditing is a weaker auditor.
     - Before 2026-09-30 this was left to the agent and it went both ways on one board: the G3.T102 and G3.T103
       verdicts were written by the verifier itself, while on G4.T003 it returned PASS with zero defects and then
       declined to write the file, naming its own boundary (kit item IN-20260930171512-b5d0). A missing verdict file
       is invisible unless the builder notices, and step 8 then hands off a row whose verdict artifact does not exist.
   - **PASS**: go to step 8. Advisory findings are accepted or logged as follow-ups (Auto-accept), never a stop.
   - **FAIL**: one fix pass (steps 5 to 7). A second FAIL marks the task `failed`, which returns it to `ticketed` with
     both verdicts in history. If the verdict says the ticket itself is wrong, it returns to `planned` for re-authoring.
   - **A verifier that produces nothing is a stall, not a verdict.** A verifier that has run 30 minutes with zero
     output bytes, and left the worktree untouched over that time, is stopped and relaunched. Beat the claim while
     waiting. Before the relaunch, re-prove the worktree against the exported patch (byte-identical, CR stripped) so
     the new verifier grades the same content, and log one history line naming the stall, how long it ran and the
     HEAD. A relaunch is not a FAIL and does not count toward the two-verdict limit.
     - On 2026-09-30 a second verifier on G1.T16 ran FIVE HOURS with zero output bytes and no answer to a direct
       status message. The builder beat its claim throughout, so no watchdog could see it, and the row went 430
       minutes with no history line on a 115 minute estimate. The builder found it and relaunched unaided; this rule
       is here so the next one does not need five hours to reach the same conclusion.
8. **Hand off** (under the lock). Set `artifacts.patch`, `artifacts.verdict` and the base fingerprint, set state
   `built`, clear the claim, and append history. Add the worktree path to `.streams\owner\worktrees.md` (task, path,
   state). Go to step 2.
9. **Idle.** When nothing is claimable, end the cycle with ScheduleWakeup at about 1800 s (noop). Every wake re-reads
   the whole session context to find no work, so an idle session waking every 10 minutes cost about six full-context
   calls an hour for nothing (owner ruling 2026-10-03, cost review). A busy session still reads its inbox at the start
   of every cycle; only an idle session's inbox waits up to 30 minutes. When every group is
   `closed`, stop the loop.

## Tasks that deliver in place under `.streams`

A task whose write set lies ENTIRELY under `.streams\` has NO patch, because `.streams/` is in `.git/info/exclude`:
git never reports those files, so a worktree base cannot carry them, `git diff` cannot see them and
`Export-TaskPatch.ps1` refuses with `IN-PLACE <task> ...` rather than `EMPTY`. Two kinds of row are shaped this way
today: a grader repair (`.streams\graders\<task>.ps1`) and an AC-coverage audit
(`.streams\plans\<group>.ac-audit.md`).

Build one like a mockup task, not like a code task:

- Do NOT create a worktree. Write the artifact in the main tree, where its grader reads it.
- Run the task's grader (`Invoke-Grader.ps1 -Root <repo>`), and the blind verifier against the ticket's checks.
- On PASS move the task to `built` with the ARTIFACT's own path in `artifacts.patch`
  (for example `.streams\graders\G1.T02.ps1`).
- The integrator lands it with no tree change and no commit: `INTEGRATED <task> (in place)`.

This is the one case where a builder writes under `.streams\graders\` or `.streams\plans\`, and only for the
paths its own write set names.

## Mockup tasks

A `mockup` task has no patch. The builder produces the screens with ui-ux-pro-max in the repo's standing layout, writes
them to `<repo>\Documentation\mockups\<task>\` (HTML, CSS and SVG are committed; PNGs and other binaries are
gitignored there), publishes or refreshes the gallery artifact, and runs
the blind verifier against the ticket's checks. On PASS the task goes to `built` with the gallery link in
`artifacts.patch`. The owner's look is the separate `gate` task that follows it.

## Host failures that lie

A build failure that blames the host is checked against the host before it is believed.

- **`MSB3021` / "There is not enough space on the disk"** is name-space exhaustion, not disk space, until free space is
  actually measured. `GetTempFileName` draws one name out of 65,536 per folder. On 2026-09-29 CORPLTR94 had 11 GB free
  on C: and about 65,535 stale `tmp*.tmp` files in `%TEMP%`; a solution build and `Export-TaskPatch.ps1` both failed in
  worktree `G4.T006` until those files were deleted, after which the same commands succeeded unchanged. The watchdog now
  sweeps stale `tmp*.tmp` files and stale `speedy-*` folders out of the host temp folder every status cycle, so treat a
  fresh occurrence as a test or tool creating them faster than the sweep clears them and say so in an inbox item.
- **`StringAssert.DoesNotContain` does not exist in MSTest 4.3.3.** The compile error reads like a missing package or a
  wrong `using`; the method is simply `Assert.DoesNotContain`.
- **`Tests.Web` already reaches `Infrastructure` transitively** through Web and Composition, so a type such as
  `BackupService.ExclusionStatement` needs no csproj change to be visible from a Web test.
- **`CS2012` on `obj\`** is two builds of the same tree at once, not a code defect. Grade the main tree only through
  `Invoke-Grader.ps1`, which holds `.streams\main-grader.lock`.

## Claims and liveness

- Refresh `claim.beat` under the lock at each step boundary, and at least every 10 minutes during step 5.
- A claim whose `beat` is older than 45 minutes is stale. Another builder may take it over. It logs the takeover, keeps
  the old worktree listed for the owner, and starts a new worktree named `<task>-2`.
- A session that finds its claim taken over stops that task. It leaves its worktree in place and claims another.

## Rules

- Writes ONLY:
  - its own worktree;
  - `.streams\patches\`, `.streams\logs\`, `.streams\verdicts\`, `.streams\owner\worktrees.md`, and its own row's
    check `.streams\checks\<task>.ps1`;
  - the write-set paths of a task that delivers in place under `.streams` (see that section), and nothing else there;
  - `.streams\decisions.md`, only through `Update-Task.ps1 -AddWriteSet` (the script appends the line);
  - inbox lines, only through `Set-InboxItem.ps1` and `Send-InboxItem.ps1` (append-only, under the inbox lock);
  - the task fields `state / claim / artifacts / base / history`, and additions to its own `writeSet`, through the lock.
- Never changes the main tree, the ticket, the grader or `dependsOn`, and never removes a path from a write set or
  adds one another open task owns. A wrong ticket or grader sends the task back to `planned` with the reason.
- Never prompts the owner. Every choice the builder can make is auto-accepted and logged (Auto-accept).
- Never removes a worktree. Removal is the owner's call, from `.streams\owner\worktrees.md`.
- Never redirects a command's output into the repo. An `errs.txt` sat untracked in the main tree root on 2026-09-29
  holding one line of git stderr from an ad-hoc `2> errs.txt`, owned by nobody and read by nobody. A log goes under
  `.streams\logs\` or into the session scratchpad. The watchdog now prints a `JUNK` note for anything left in the root.
- Never commits, never branches, never stashes in the main tree.
- **Stops only processes it started, by the PID it recorded when it started them** (`$p = Start-Process -PassThru`,
  then `Stop-Process -Id $p.Id`; the PID a background command printed; `taskkill /PID <pid> /T`). Never by name or
  command-line pattern: no `pkill`, `killall`, `pgrep | xargs kill`, `taskkill /IM` or `/FI`, `Stop-Process -Name`,
  `Get-Process <name> | Stop-Process`, `wmic process where name=...`. The stream host is shared: on 2026-10-09 one
  builder asked for `pkill -f Invoke-Grader.ps1` and another for `pkill -f python`, which would have killed every other
  builder's grader and the integrator's suite. Both sat on an owner prompt with their unit timeout paused, so two of
  five build slots stood idle. A `-Live` unit's stream-unit mod now REFUSES such a command outright instead of prompting.
  A hung child you did not record is not yours to stop: let the unit's limit end it, or name it in an inbox item.

## Scripts (in `${CLAUDE_SKILL_DIR}\..\stream-kit\scripts\`)

- Step 0: `Get-InboxItems.ps1 -Skill stream-build -Open`, then
  `Set-InboxItem.ps1 -Skill stream-build -Id <id> -By <session> -Status taken|done|declined|forwarded [-Note] [-ForwardTo]`
  (exit 8 = someone else has it, or you do not hold it).
- Step 3b: `Restore-TaskPatch.ps1 -Task <t> -Worktree <path>`: exit 0 `APPLIED`, 1 `NO-PRIOR`, 2 `CONFLICT`.

- Step 2: `Claim-Task.ps1 -Role build -Session <id>` claims the task and moves it to `building`. `-Task <id>` claims
  one named row under the same gates. The sort skips a row named by a live `taken` inbox item, since its grader may
  be under rewrite; the skip is a warning, and `-Task` overrides it.
- Step 3: `New-TaskWorktree.ps1 -Task <t> -Session <id>` prints the worktree path.
- Steps 4 and 5: `Invoke-Grader.ps1 -Task <t> -Root <worktree> -Only grader -Label red -ExpectRed` (4a, author
  grader only, no edit yet), `-Only check -Label red-check -ExpectRed` (4b, clause tests written, nothing
  implemented), then `-Label wt` (both scripts). `NO-GRADER` (exit 4) under `-Only grader` means the row has no author
  grader: skip 4a. Add `-BeatSession <id> -BeatTask <t>` to every run: the grader beats the claim every 30 seconds while it runs, so work
  longer than the watchdog's 45 minutes is not broken as an abandoned claim.
  A bare `dotnet test` beats NOTHING, so a long test run outside the grader is how a claim goes stale mid-build: beat
  it with `Update-Task.ps1 -Beat` every few minutes, or run it through the grader. Since 2026-09-29 the watchdog
  exports and attaches a patch before it reaps, so this now costs the build output rather than the work - but the
  claim still breaks and another builder can take the task out from under you.
- Step 6: `Export-TaskPatch.ps1 -Task <t> -Worktree <path>`. Exit 2 lists `OUTSIDE` files; widen with
  `Update-Task.ps1 -Role build -AddWriteSet <file[,file]> -Note "<why>"` (exit 7 = `WRITESET-OVERLAP`, nothing written),
  then export again.
- Step 8: `Update-Task.ps1 -Role build -To built -Release -Artifacts @{patch='.streams\patches\<t>.patch'; verdict='.streams\verdicts\<t>.md'; testRecord='.streams\verdicts\<t>.tests.md'}`.
  A row handed off without `artifacts.check` cannot be re-verified on main except by an author grader; a row with
  neither is bounced by the integrator.
  The failure moves use `-To ticketed`, `-To planned` or `-To blocked`, each with `-Note`. Exit 3 = CLAIM-LOST.
