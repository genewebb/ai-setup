---
name: stream-author
description: v0.12. Stream kit skill 2 of 5. It runs unattended and never prompts. Each cycle it first takes the oldest open item in its inbox (.streams\inbox\stream-author.md, to rewrite a ticket or grader, including for a ticketed task no builder has claimed), then claims released tasks from .streams\tasks.json, writes a short ticket whose acceptance clauses state WHAT must be true (with REQ/AC ids and the write set), optionally a static grader, has one skeptic subagent try to break them, and then marks the task ticketed for builders. It runs no RED check and builds nothing; the builder proves RED in its own worktree and chooses the tests. When nothing is ready it sleeps and re-checks. Use for /stream-author (run under /loop), /stream-author once, /stream-author status.
---

# stream-author

Skill 2 of the stream kit. It turns `planned` tasks into `ticketed` tasks that a builder can take without asking anything.
It never prompts. Anything the requirement text leaves open gets the recommended reading, is logged for the owner, and
the work continues.

## Start

```
/loop /stream-author repo: {SpeedyRepo}
```

**Fresh context (preferred; owner ruling 2026-10-04).** Instead of `/loop`, run this role from a plain terminal with
`pwsh -NoProfile -File "{ClaudeHome}\skills\stream-kit\scripts\Start-StreamRunner.ps1" -Repo {SpeedyRepo} -Role author`.
The runner starts a new headless Claude session for every ticket, so nothing carries over from the last one's
context. Each runner session gets its session id and the headless rules in its system prompt:
- run one cycle;
- never call ScheduleWakeup;
- never end the turn while its own work is still running;
- start anything that must outlive the session (an integrator suite, a drain) detached with `Start-Process`.

The `/loop` form above still works.The runner launches only when there is something to take: an actionable inbox item, or a row the claim would offer.
Otherwise it sleeps 30 minutes at no token cost.

**Watch it live (owner ruling 2026-10-04).** Add `-Live` to the runner line to run each unit as an interactive session in the
runner's own terminal, with Remote Control only when the runner line adds -Remote (claude.ai/code and the Claude app then list it under its session id), or
`-Stream` for a live text feed of a `-p` session. Under `-Live` the cycle ends with one call to
`mcp__stream-unit__unit_done` (outcome `built`, `ticketed`, `planned`, `integrated`, `done`, `idle`, `blocked` or
`failed`, and a one-line note), made only after every result of the cycle is written under `.streams\`; the session
then exits by itself. A session without that tool (a `/loop` session, `-p`) ends the cycle as before.

**Pre-staged units (2026-10-06, prestage-runner-design).** The runner does steps 0 to 2 itself, in PowerShell, before it
starts you: it takes the oldest actionable inbox item in your session's name OR claims the next row with
`Claim-Task.ps1` (the gate's own selector), and writes a PACKET under `.streams\units\<session>\`: `task.json` (the
row) and `unit.md` (the held item, the row summary and artifact paths, the STALE note, requirement excerpts per `why`
id, and the lessons). Your command then ends with `packet: <path to unit.md>` and your rules name it. **Read `unit.md`
first and skip steps 0 to 2**: the inbox is already read, the item already taken, the row already claimed by your
session, the lessons already in the packet. One item OR one row per unit; do not take or claim anything else, and end
the unit when that work is done - the runner starts the next unit at once. A row the runner chose is yours under the
owner's focus rule; a lesson never vetoes it. A `/loop` session or a plain `once` with no `packet:` does steps 0 to 2
itself as before.

**Models are configuration.** `.streams\config.json` (written by the runner with empty fields the first time) sets
per role, or for every role, the unit's `model`, its `subagentModel` (the skeptic), `effort` and `promptCacheTtl`;
the runner reads it before every unit, so an edit takes effect at the next unit. When your rules name a subagent
model, put it on every `Agent` call, whatever step 7 says.

**Lessons.** A runner session starts empty, so it reads `.streams\lessons\author.md` before it claims or takes work
(in a pre-staged unit the packet holds them): one line per
lesson from earlier units of this role. Add one only for something a later unit needs and cannot read from `.streams\`:
`pwsh -NoProfile -File "{ClaudeHome}\skills\stream-kit\scripts\Add-Lesson.ps1" -Repo {SpeedyRepo} -Role author -Session <id> -Task <id> -Text "<one line>"`.
Never ticket detail, never a secret.

Run it under `/loop` (dynamic) so it paces itself. Several author sessions can run at once, because claims are atomic.
`/stream-author once` authors one task and stops. `/stream-author status` is read-only.

## One cycle

FOCUS (2026-10-05, priority-focus-design 3.1; owner-set since 2026-10-06): you are offered rows from the FOCUS SET only -
the rows of the focus group(s), plus the rows their work depends on (`lib\Streams.ps1 Get-FocusSet`). The owner names
the focus group(s) in `.streams\config.json` as `"focus": { "groups": ["G4"] }` (one or more); an empty list means the
first unclosed group in board order. Never file an author or build inbox item about a row outside the focus
(`Send-InboxItem.ps1` refuses it: NOT-FOCUS). `Integrate-Patch.ps1` prints NOT-FOCUS for a built row outside the focus
and leaves it built.
AUTHOR SPILL (owner ruling 2026-10-12): authors have their own queue. When the focus set has no planned row for you,
`Claim-Task.ps1` offers the planned rows of every other released group instead: the next group in board order first,
then ready-first and the longest chain, as in the focus sort. The claim's history note says `author spill` and stamps
the main commit you write against (the row's `spill` field). Author it exactly as a focus row; it waits in `ticketed`
until its group is focus, because builders never spill. Never choose a non-focus row yourself: take what the claim
gives. A claim that reads NONE means no released group has a planned row for you.
PRE-STAGED UNIT: when your command carries `packet:`, steps 0, 1 and 2 are DONE by the runner. Read the packet's
`unit.md`, then continue at step 3 (a claimed row) or do the held item's work (an item). Never run them again.
0. **Inbox.** List `<repo>\.streams\inbox\stream-author.md` (its contract is at the top of the file) with
   `Get-InboxItems.ps1 -Skill stream-author -Open`, and take the OLDEST open item before claiming a planned task.
   - Take it with `Set-InboxItem.ps1 -Status taken`. Exit 8 (`ALREADY`) means another session has it: skip it and take
     the next. Never append `taken` by hand; the script checks the item's latest line under a lock, so two authors can
     never work the same item.
   - Allowed: rewriting a ticket or grader under `.streams\tickets\` or `.streams\graders\`, including for a task that
     is already `ticketed` and not yet claimed by a builder. Close it with `Set-InboxItem.ps1 -Status done` or
     `declined` and the reason.
   - To record a new or moved grader (or ticket) path on such a row, `Update-Task.ps1 -Role author -Session <you>
     -Task <id> -Artifacts '{"grader":".streams\\graders\\<id>.ps1"}'` works WITHOUT a claim while you hold the taken
     item that names the row: `-Artifacts` alone, on a `ticketed` row nobody has claimed. Anything more is `REFUSED`
     (exit 2); another session gets `CLAIM-LOST` (exit 3). Before 2026-10-10 no script could do it (kit item
     IN-20261010152029-7e12, G6.T019).
   - After ANY grader change, run the portability lint and the skeptic (step 7) on that grader before appending
     `done`. There is no author RED run any more (step 6).
   - **BEAT THE ITEM inside any step that can outlast the 30-minute inbox limit**, the skeptic round above all:
     `Set-InboxItem.ps1 -Skill stream-author -Id <id> -By <session> -Status beat -Note '<what is running>'`. An item
     has no other heartbeat, so a holder that is working and a holder that died read identically and the watchdog
     re-opens the item. On 2026-09-30 one 54-minute skeptic round inside an item cost exactly that: the item came back
     open at 89 minutes, a second author took it, and both sessions wrote the same six files inside twenty minutes
     (kit item IN-20260930173837-50cb). A beat moves the hold's clock and nothing else, and only the holder may beat.
   - When an item changes a grader, keep `artifacts.patch` untouched: a builder's patch stays valid evidence, and
     only the grader and its hash are replaced.
   - Anything else is forwarded: `Set-InboxItem.ps1 -Status forwarded -ForwardTo <skill>` (`stream-kit`, `stream-plan`,
     `stream-build`, `stream-integrate`, `stream-status`) writes both lines.
   - Then continue with step 1 (or step 2 once the session has an identity).
1. **Identity.** On first wake, pick a session id `author-<yyyyMMddHHmm>-<4 hex>` and keep it for the session.
2. **Claim** (under the `tasks.json` lock). Take the first task that meets all of these:
   - its state is `planned`;
   - its group is `released`;
   - it has no live claim;
   - its kind is `code`, `mockup`, `docs` or `integration` (a `gate` task needs no ticket, so it goes straight to
     `ticketed`).

   Critical-path tasks come first, then the oldest `releasedAt`. Set `claim = {session, role: "author", at, beat}`.
   Dependencies do NOT have to be built first: authoring can run ahead of building.

   **REFRESH MODE** (2026-10-05 priority-focus-design 3.2). When the claimed row's latest history note carries
   `STALE: <files> since <sha> by <rows>` (written through `Revise-Task.ps1` by `Activate-Group.ps1` when the group
   became the focus group, so the note reads `plan revise: release planned -- STALE: ...`),
   the row already has a ticket and a grader written against older code. Do not author it from scratch:
   - read the existing ticket and grader, and `git diff <sha>..HEAD -- <files>` for exactly the files the note names;
   - update ONLY the clauses and grader checks those changes touch; keep every other clause word for word;
   - keep `artifacts.patch` if one exists (a builder's patch stays valid evidence); the grader hash is replaced as
     usual when the grader changes;
   - one skeptic pass (step 7) on the changed grader, then `ticketed` as usual.
   A refresh that finds the change does not affect the ticket still re-tickets it, with a note saying so.
3. **Read** the task's `why` clauses from the requirement paths in `tasks.json`, its write set, and the code needed to
   state the change. Read nothing outside that.
4. **Write the ticket** to `.streams\tickets\<task>.md`:
   - **What**: the change in plain terms, per clause.
   - **Why**: the REQ/AC ids, each quoted in one line.
   - **Write set**: copied from the task. The builder may touch nothing else.
   - **Acceptance clauses**: numbered (A1, A2, ...). Each says WHAT must be true after the change, observable and
     testable, with its REQ/AC id, and the reason it is false today (the reason the builder's RED must show). The
     builder chooses and writes the tests for them; the ticket does not have to name tests or filters. Name one only
     where a specific existing test is the clause's evidence.
   - **Defaults taken**: any reading the author chose, with the owner-log line.
   - **Not in this task**: the nearby work that belongs to another task (by id).
5. **Grader (optional).** A per-task grader is no longer the release gate: the builder writes a check that runs one
   test per acceptance clause plus the existing tests its change can break, and the integrator re-runs that check on
   main (owner ruling 2026-10-02, kit item IN-20261002160643-741d). Write a grader only for a clause no test can carry,
   such as a static pin over a file the change must contain, and give its clauses the ticket's A-ids. A row that
   already has a grader keeps it; builder and integrator run it as one more check. When you write one, it goes to
   `.streams\graders\<task>.ps1` under this contract:
   - `param([string]$Root)`. It runs against any tree (the main tree or a worktree).
   - It checks one clause per C-id: a targeted `dotnet test --filter`, a static pin (a regex over a file), or a captured
     output check.
   - It prints one `PASS Cn` or `FAIL Cn: <reason>` line per clause and exits 0 only when every clause passes.
   - It never runs a whole suite and never runs another task's grader. Suites belong to the integration task.
   - It must survive the build-then-apply handoff: the same content must grade the same in a worktree and on main
     after `git apply`. So it never compares file times, never reads MyLoop state (`.loop\rows`), and never reads a
     path outside the tree it is given. Evidence that must be fresh is compared with `$env:STREAM_SINCE_UTC`, which
     `Invoke-Grader.ps1` sets (the claim time; for an integration task, the group's latest integration).
   - It pins CONTENT, never a commit id. A history re-import replaces commit ids: `909a2f1e11` was gone on
     2026-09-29 and every G2.T01 clause that read its baseline with `git cat-file blob <sha>:<path>` then reported
     FAIL, so a correct grader read as a total failure. Carry a baseline as a SHA-256 pin, or as a base64 blob checked
     against a SHA-256 after decoding, and ask git nothing. A grader that must resolve a commit fails loudly with the
     re-pin instruction rather than reporting a clause FAIL.
   - It never delegates a clause to a script outside the tree. `G1.T01` sent 19 of its 21 clauses to
     `.loop\criteria\rd-25.ps1`; `.loop` was wiped on 2026-09-26 and every one of those clauses has printed nothing
     since, so the grader can never pass and its red says nothing about the code. The lint flags `COMMIT-PIN`,
     `OUTSIDE-TREE` and `DEAD-DELEGATE` for exactly these.
   - It never asserts the ABSENCE of something in a file OUTSIDE its row's write set. A grader is re-run on main at
     group close-out, and by then a later row has legitimately edited that file, so the clause reports a defect the
     board itself planned. Measured on 2026-09-30: G3.T079's C7 failed on main with "CliRunner.cs references
     SetupCompletionService (the CLI gate is not in this task)" - and G3.T079's own title says the CLI half moved to
     G3.T153, which is integrated and is the row that added that reference. Scope lives in the ticket and in the write
     set, which `Export-TaskPatch.ps1` already enforces; a negative clause about somebody else's file is a scope check
     that rots. Pin what THIS row's files do, not what another row's file must not.
   - A clause that reads a trx result by name trims it: MSTest writes a DataRow result as `MyTest ("arg")`, so
     `($r.Node.testName -split '\(')[0]` keeps a trailing space and a test that ran reads as "did not run". Use
     `((...)[0]).Trim()`, or map `testId` to the method name; the lint flags `UNTRIMMED-TESTNAME`. Each grader keeps its
     own reader: a shared helper outside the tree is the delegate the rule above forbids.
   - A `mockup` grader that shoots renders has the shooter record, for EVERY render, `widestElementOverflow`: the
     largest `scrollWidth - clientWidth` over all elements, clamped at 0, written into `renders.json`. One clause
     requires that figure on every entry and requires it to be 0. G4.T043 passed 22 of 22 clauses on a sheet whose
     inspector row rendered one letter per line at both widths: a collapsed grid track or a clipped element shows up
     ONLY in that figure, because the document itself stays exactly as wide as the viewport, so a
     `documentElement.scrollWidth` clause reads clean. The clause handles three traps:
     - ConvertFrom-Json keeps the LAST of two identical keys without a word, so count the `"widestElementOverflow":`
       keys in the file text and require one per entry.
     - A one-element list renders as the string `0`, so refuse a value that is a list.
     - Parse with `[double]::TryParse(..., InvariantCulture)`, because `0.5` reads as `5` on de-DE.

     An entry without the field fails, so an older shooter cannot pass silently. Copy
     the reference clause, C23 in `.streams\graders\G4.T043.ps1` (shooter: `.streams\mockups\G4b\flow-canvas\shoot-canvas.mjs:62-85`).
     Limit: the figure counts internal scroll overflow, so a `text-overflow: ellipsis` label or an intended
     `overflow-x: auto` scroller reds the clause; a design that needs one changes the metric and the clause together
     through an inbox item, never by waiving it. Measure the vertical axis the same way (`scrollHeight -
     clientHeight`) when the sheet has fixed-height regions (kit item IN-20260930205745-7485).
     A shell mockup that keeps the page frame carries elements that clip BY DESIGN: the Bootstrap
     `.visually-hidden-focusable` skip link (MainLayout.razor:38) and, in a collapsed-sidebar frame, the zero-width
     `.sidebar` subtree. Exempt only those, by name: the shooter writes an `overflowExempt` list (selector and reason)
     into each entry and leaves them out of `widestElementOverflow`, and a separate `documentOverflow`
     (`documentElement.scrollWidth - clientWidth`) must be 0. The clause fails an exempt name it does not know. Reference:
     `.streams\tickets\G5.T008.md` A6 (kit item IN-20261003175459-562a).
   - `Test-GraderPortability.ps1 -Grader <file>` must print `PORTABLE`. Run it on every grader you write, and on any
     grader you did not write (an import shim and the grader it calls) before you change it.
6. **No RED run here.** The RED check moved to the FIRST step of the build (owner ruling 2026-10-02, kit item
   IN-20261002160453-ce2a). An author RED ran the grader against the main tree under `.streams\main-grader.lock`, so
   every author waited behind any long main-tree run: on 2026-10-02, 23 rows sat planned with the note "RED rerun
   queued behind G2 suites run 4", among them all four roots the 17 ticketed code rows waited on, and builders read 0
   claimable for over two hours. The builder now proves RED in its private worktree, which needs no lock, and bounces
   the row back to `planned` with the output when a clause is not red for the ticket's reason. A row whose last note
   is a queued RED re-run is released under this rule at once (step 8). Never run `dotnet build` or `dotnet test`
   against the main tree; an exploratory build goes in a scratch worktree outside the repo:
   `git worktree add --detach {WorktreesRoot}\<repo>-scratch\<task>-<purpose>`.
7. **Skeptic.** Beat first (`Update-Task.ps1 -Beat`), then launch the skeptic as a background subagent and beat at
   least every 10 minutes until it returns. The skeptic alone can outlast the 30-minute claim limit. An author that goes
   quiet while it waits loses the task to a takeover, and its work is done twice.
   **EVERY BEAT IN THIS STEP CARRIES A NOTE**: `Update-Task.ps1 -Beat -Note 'skeptic round: <what is running>'`. A
   bare beat says the session is alive and nothing more, so the watchdog's no-progress rule takes the claim after 60
   minutes of a row that has not moved - and this step by design moves nothing, because touching the ticket or the
   grader while a blind reader is inside it invalidates the round. The note is a history line, so a noted wait counts
   as progress and the claim survives. Measured on G3.T184 on 2026-09-30: a 72-minute round beat every few minutes,
   the claim went anyway, and an 11-clause ticket, a PORTABLE grader, a proved RED and two builder probes had to be
   handed off instead of released (kit item IN-20260930224214-efe5). The rule itself is right and is not going away:
   G4.T039 beat for 19h14m with its ticket and grader written and applied nothing, so a skeptic round and a zombie
   are identical on disk. The note is what tells them apart, and it also makes a round that really has hung visible.
   Launch the skeptic with `model: "sonnet"` on the Agent call, unless your runner rules name another subagent model
   from `.streams\config.json` (that wins). It reads and refutes and builds nothing, and on Opus
   it was about 31% of all author spend (owner ruling 2026-10-03, cost review).
   One fresh subagent gets the requirement clauses, the ticket and the grader when there is one, and never the
   author's reasoning. It runs nothing: it reads. It is told to REFUTE. It looks for:
   - a requirement clause with no acceptance clause, or an acceptance clause that is not observable or not testable;
   - a clause whose stated "false today" reason is wrong, judged from the code and the grader TEXT, not from a run;
   - a grader check a wrong change could pass;
   - a write-set leak (the change needs a file outside the set). This one the author FIXES rather than blocks on:
     widen the row's own write set with `Update-Task.ps1 -Role author -AddWriteSet <file[,file]> -Note "<why>"`
     (auto-accepted, logged to `decisions.md`; owner ruling 2026-10-17, after 234 of 291 author blocks were leaks).
     Only a `WRITESET-OVERLAP` refusal (exit 7: the file belongs to another open, unordered task) blocks the task,
     with the overlapping task named in the history;
   - a test the ticket names that is not atomic or uses fixtures from outside the repo.

   The author fixes each finding or records why it is not one. There is one skeptic round. A finding that still
   stands after it marks the task `blocked` with that finding in the task's history.
8. **Release.** Under the lock: set `artifacts.ticket` (and `artifacts.grader` when you wrote one), set state
   `ticketed`, clear the claim, and append history. Then go to step 2.
9. **Idle.** When nothing is claimable, end the cycle with ScheduleWakeup at about 1800 s (noop). Every wake re-reads
   the whole session context to find no work, so an idle session waking every 10 minutes cost about six full-context
   calls an hour for nothing (owner ruling 2026-10-03, cost review). A busy session still reads its inbox at the start
   of every cycle; only an idle session's inbox waits up to 30 minutes. When every group is
   `closed`, stop the loop.

## Unknowns

- Take the recommended reading and carry on.
- Append one line to `.streams\owner\questions.md`: `<task> | question | default applied | why`. Four fields, no
  leading `- `. Only a question with NO safe default is an escalation for the owner, written
  `ESCALATE <task> | question | why no default`; the status board counts escalations by that shape (kit item
  IN-20261004203020-5f5e).
- If the owner overrides it later, that becomes a fix task (added by `stream-integrate` or by `/stream-plan revise`).
  This task is not held.

## Claims and liveness

- Refresh `claim.beat` under the lock at each step boundary (3 to 8), and at least every 10 minutes during step 7.
  In step 7 every beat carries `-Note`: a bare beat is not progress and the no-progress rule takes the claim.
- A claim whose `beat` is older than 30 minutes is stale. Any author may take it over; the takeover is logged in the
  task's history and the old session's partial ticket is overwritten.
- A session that finds its own claim gone (taken over) stops that task and claims another.

## Rules

- Writes ONLY `.streams\tickets\`, `.streams\graders\`, `.streams\owner\questions.md`, appended lines in
  `.streams\inbox\*.md`, and task fields
  `state / claim / artifacts / history` through the lock.
- Never edits product code or tests. Graders read the tree; they never change it.
- Never changes a task's `why` or `dependsOn`, and never narrows or rewrites its write set. A wrong one marks the task
  `blocked` with the reason, for `/stream-plan revise`. The one write-set change it makes is widening its own claimed
  row with `-AddWriteSet` (step 7), which the script refuses when the file belongs to another open task.
- An `import`ed task that arrives `ticketed` is not re-authored, except through an inbox item (step 0).
- Inbox items: only through `Set-InboxItem.ps1` and `Send-InboxItem.ps1` (append-only, under the inbox lock).
- Never redirects a command's output into the repo. An `errs.txt` sat untracked in the main tree root on 2026-09-29
  holding one line of git stderr from an ad-hoc `2> errs.txt`, owned by nobody and read by nobody. A log goes under
  `.streams\logs\` or into the session scratchpad. The watchdog now prints a `JUNK` note for anything left in the root.
- Never commits, never branches.
- **A multi-step probe with shell variables or `$(...)` runs as one script file.** Claude Code's own check prompts on
  a compound Bash command whose variables or command substitutions it cannot read ahead ("A variable in this command
  can't be checked before it runs", "This Bash command contains multiple operations"), and no allow rule was found
  that turns that check off. Write the steps to a file in the session scratchpad and run it as one call:
  `pwsh -NoProfile -File <scratchpad>\probe.ps1` or `bash <scratchpad>/probe.sh`. On 2026-10-26 two builders sat on
  such prompts while probing the e2e stack with docker (kit item IN-20261026165829-709d). Container paths in docker
  arguments (`--entrypoint /bin/sh`, `-v <host>:/cmd.sh`, `docker cp <name>:/x`) no longer trip the destructive-path guard.

## Scripts (in `${CLAUDE_SKILL_DIR}\..\stream-kit\scripts\`)

- Step 0: `Get-InboxItems.ps1 -Skill stream-author -Open` lists the open items, oldest first. Then
  `Set-InboxItem.ps1 -Skill stream-author -Id <id> -By <session> -Status taken|beat|note|done|declined|forwarded [-Note] [-ForwardTo] [-Steal]`
  (exit 8 = someone else has it, or you do not hold it). `beat` keeps a long-running hold; nobody may beat another
  session's item. `note` corrects or adds to the record of an item you hold or closed. Closing an item another
  session holds needs `-Steal`, and only once that hold is past the 30-minute limit; the line then says it was
  stolen and from whom.
- Step 5: `Test-GraderPortability.ps1 -Grader .streams\graders\<t>.ps1` (exit 0 = PORTABLE; a `# portable: CODE reason`
  line in the grader waives a flag you have checked is harmless).

- Step 2: `Claim-Task.ps1 -Role author -Session <id>` prints the task JSON, or `NONE` (go to step 9).
  - `-Task <id>` claims that row instead of the sort's pick, and it is how an inbox item that names a row gets
    finished: without a claim, `planned -> ticketed` answers `CLAIM-LOST`, whoever wrote the ticket and the grader.
    It applies the same gates as the sort and refuses with `REFUSED-TASK <id> : <gate>` and exit 2.
  - The sort steps over a row named by a live `taken` inbox item in any inbox, and says so as a warning. That row's
    ticket or grader is being rewritten by the session holding the item; claiming it wrote three useless claim and
    release pairs on G3.T140 on 2026-09-30. If you hold that item, `-Task` overrides the skip - and hash the
    artifacts first, because the other session may still be writing.
- Beats and fields: `Update-Task.ps1 -Role author -Session <id> -Beat`, and
  `-Artifacts @{ticket='.streams\tickets\<t>.md'; grader='.streams\graders\<t>.ps1'}`.
- Step 8: `Update-Task.ps1 -Role author -To ticketed -Release -Note "..."`. Exit 3 = CLAIM-LOST: drop the task.
