---
name: stream-integrate
description: v0.20. Stream kit skill 4 of 5. It runs unattended, never prompts, and there is only ever one running per repo. It wakes at least every 10 minutes, even while a suite run is going, and each cycle first handles the oldest open item in its inbox (.streams\inbox\stream-integrate.md), then applies each built, verified patch to the dirty main tree as soon as it is ready and re-runs that task's grader there. When a whole group is integrated it starts one Tier 2 run (Start-SuiteRun.ps1, in a snapshot of main, so main stays open), the scripts screen flaky tests and attribute failures to fix tasks, a Tier 3 retest runs only the failed tests once the fixes land, and Test-GroupClose.ps1 says when the group may close; then it activates the next group (Activate-Group.ps1). Use for /stream-integrate (run under /loop), /stream-integrate once, /stream-integrate gate <task> pass|fail "<note>", /stream-integrate status.
---

# stream-integrate

Skill 4 of the stream kit. It is the only stream skill that writes the main tree, and the only one that commits, with one exception: stream-adhoc lands an owner-approved ad-hoc change through `Commit-AdhocChange.ps1`, which takes `integrate-patch.lock` and `main-grader.lock` first, so it never runs inside an Integrate-Patch run. A built patch that no longer applies after an ad-hoc commit takes the usual REBASE path. Each patch is
committed as soon as its grader passes on main, so the main tree's history only ever holds verified patches.

## Start

```
/loop /stream-integrate repo: {SpeedyRepo}
```

**Fresh context (preferred; owner ruling 2026-10-04).** Instead of `/loop`, run this role from a plain terminal with
`pwsh -NoProfile -File "{ClaudeHome}\skills\stream-kit\scripts\Start-StreamRunner.ps1" -Repo {SpeedyRepo} -Role integrate`.
The runner launches a new headless Claude session only when its gate finds work (owner ruling 2026-10-17): an open
inbox item, a built focus row the drain can apply (`Get-Claimable` integrate), a focus group in `integrating`, or this
runner's own integrator lock still beating (a suite or drain in flight). Otherwise it shows an idle report (why idle,
when it looks again) and watches `tasks.json` and its inbox file at no token cost. Nothing carries over from one unit
to the next. Each runner session gets its session id and the headless rules in its system prompt:
- run one cycle;
- never call ScheduleWakeup;
- never end the turn while its own work is still running;
- start anything that must outlive the session (an integrator suite, a drain) detached with `Start-Process`.

The `/loop` form above still works. Session id (2026-10-05, priority-focus-design 3.5): the `session: <id>` in your start prompt (`<role>-<8 hex>`, chosen by the tab launcher so the cost ledger can find your transcript). Use it on every script call. Without one in the prompt, make one as before.

Under the runner, every cycle uses the runner's one fixed session id, so the integrator lock carries over from cycle
to cycle. A suite or drain started detached keeps running after its session exits. The next cycle polls its log,
never starting a second run.

**Watch it live (owner ruling 2026-10-04).** Add `-Live` to the runner line to run each unit as an interactive session in the
runner's own terminal, with Remote Control on (claude.ai/code and the Claude app list it under its session id), or
`-Stream` for a live text feed of a `-p` session. Under `-Live` the cycle ends with one call to
`mcp__stream-unit__unit_done` (outcome `built`, `ticketed`, `planned`, `integrated`, `done`, `idle`, `blocked` or
`failed`, and a one-line note), made only after every result of the cycle is written under `.streams\`; the session
then exits by itself. A session without that tool (a `/loop` session, `-p`) ends the cycle as before.

**Lessons.** A runner session starts empty, so it reads `.streams\lessons\integrate.md` before it claims or takes work: one line per
lesson from earlier units of this role. Add one only for something a later unit needs and cannot read from `.streams\`:
`pwsh -NoProfile -File "{ClaudeHome}\skills\stream-kit\scripts\Add-Lesson.ps1" -Repo {SpeedyRepo} -Role integrate -Session <id> -Task <id> -Text "<one line>"`.
Never ticket detail, never a secret.

**One integrator per repo.**
- A session takes `.streams\integrator.lock` (CreateNew, `{session, at, beat}`) before its first cycle and refreshes
  `beat` every cycle.
- A second session that finds a live lock (a beat within 20 minutes) only prints status.
- A stale lock is taken over and the takeover is logged.

## One cycle

Each cycle does the first of these that has work, then loops. It idles only when none of them has work.

### 0. Inbox

List `<repo>\.streams\inbox\stream-integrate.md` with `Get-InboxItems.ps1 -Skill stream-integrate -Open`. The file's
contract, at its top, is binding: append-only, and every line goes through `Set-InboxItem.ps1` / `Send-InboxItem.ps1`.
Handle the **oldest** open item before step A:

1. Take it with `Set-InboxItem.ps1 -Status taken` (exit 8 = someone else has it; skip it).
2. Act, but only within these allowed actions:
   - re-apply or retry a patch;
   - requeue a bounced task;
   - commit an integrated task's patch paths, exactly as step A3 would (only the paths the patch touches, message
     `<task>: <title>`); if they are already committed, verify that against the patch and change nothing;
   - answer suite and fix-task questions;
   - follow up on a gate.
   - record a row whose verified patch is already committed on main (a builder blocked it as already met):
     `Update-Task.ps1 -Role integrate -To integrated` from `blocked`, which checks that the kept patch reverse-applies
     clean on the main tree.
3. Close it with `Set-InboxItem.ps1 -Status done` and the result, or `declined` and the reason.

An item that needs a patch, ticket or grader edited, or anything else outside these actions, is never done here. It is
forwarded with `Set-InboxItem.ps1 -Status forwarded -ForwardTo <role>`, which writes both lines (stream-build for a
patch, stream-author for a ticket or grader, stream-plan for scope, stream-kit for a kit script).

**Inbox cadence: every 10 minutes, always.** The inbox is read at the start of every cycle, and a cycle starts at
least every 10 minutes for as long as the loop runs. So every `ScheduleWakeup` this skill sets is **600 s or less**,
in every state, not only when idle: while a step-B suite run, a detached drain or a long grader is still going, the
loop still wakes every 10 minutes, runs `Enter-Integrator.ps1`, works the inbox, then polls the run's log and goes
back to sleep. Never pick a longer delay because "the run takes an hour". Measured on 2026-10-02: with 25-30 minute
wakeups during G2's suite runs, plan items that asked the integrator to stop a doomed run or to apply a fix next sat
unread for up to 30 minutes. A cycle that finds nothing in the inbox and no finished run is a `noop` tick.

**Cycle status report: every cycle, required (owner ruling 2026-10-10).** Every cycle ends with a short status the
owner can read, written as visible text before `ScheduleWakeup` (or, under the runner, in the `unit_done` note). It is
required on every cadence tick, including a `noop` tick. Its first two lines are always:

1. `Inbox: <N> open` and, when N > 0, the ids. Re-run `Get-InboxItems.ps1 -Skill stream-integrate -Open` right before
   writing the report, not only at the start of the cycle: on 2026-10-10 two items arrived mid-cycle, after the
   cycle's first read, and the report would have said 0.
2. `Working: <what>` (each drain, suite run or retest in flight, with its run id or task ids) or `Idle: <why>`
   (nothing built, waiting on a fix row, a builder or the owner). Never leave the owner to infer that the loop is alive.

Then one line per change this cycle (integrated, bounced, run started or ended, item closed) and the next wake time
in local time.

### A. Apply one patch

FOCUS (2026-10-05, priority-focus-design 3.1; owner-set since 2026-10-06): you are offered rows from the FOCUS SET only -
the rows of the focus group(s), plus every unlanded row their work depends on, transitively, whatever its group
(`lib\Streams.ps1 Get-FocusSet` / `Get-FocusClosure`; since 2026-10-18 an EARLIER open group's dependency is pulled in
too, and the board names each pulled row as `FOCUS-PULL`). The owner names
the focus group(s) in `.streams\config.json` as `"focus": { "groups": ["G4"] }` (one or more); an empty list means the
first unclosed group in board order. A claim that reads NONE means the focus has nothing for you now; never look for
work in another group, and never file an author or build inbox item about a row outside the focus
(`Send-InboxItem.ps1` refuses it: NOT-FOCUS). `Integrate-Patch.ps1` prints NOT-FOCUS for a built row outside the focus
and leaves it built. With more than one focus group, "the focus group" in the steps below means each of them in turn.

1. Pick the first task that meets all of these:
   - its state is `built`;
   - its kind is `code` or `docs`;
   - every `dependsOn` task is `integrated` or `done`.

   Dependency order keeps each patch's base true. Run ONE `Integrate-Patch.ps1` at a time: a second run while one is going prints `DRAIN-BUSY` (exit 4) and does nothing, so wait for the first to print its outcome before starting the next.
   - **BASE-STALE** (before any apply; 2026-10-18 dependency review F1): the builder's base stacked its built dependencies' patches and recorded their hashes (`base.deps`). A dependency that bounced and was rebuilt since landed a DIFFERENT patch, so this row's verifier graded against code that is not on main even when its own patch still applies. The row goes to `ticketed` with the patch kept; the next build restores it on the true base (`Restore-TaskPatch.ps1`) and re-verifies.
2. Run `git -C <repo> apply --check --binary <patch>`.
   - **Clean**: apply it.
   - **Not clean, composition files only (ORDERED-BY-MERGE, kit item IN-20261018134210-ede5)**: when every failing section is a composition / registration file (lib `$script:CompositionFileRx`) whose hunks only add lines, `Integrate-Patch.ps1` re-inserts the added lines beside the unchanged lines around them on main (lib `New-CompositionMergedPatch`), prints `MERGED <id> <files>`, and applies, grades, reverses and commits `.streams\patches\<id>.merged.patch` instead. A changed or removed composition line, a missing or ambiguous anchor, or a conflict in any other file is still a REBASE (the note says why the merge was refused).
   - **Not clean, empty stray files (STRAY-EMPTY, kit item IN-20261019112954-86bc)**: a 0-byte UNTRACKED file in the main tree at a path the patch creates (left by a builder whose `[IO.File]` call with a relative path resolved against the main tree) is moved to `.streams\stray\<id>-<stamp>\`, never deleted, and the check re-run. When the patch then applies, `Integrate-Patch.ps1` prints `STRAY-EMPTY <id> <files>`, logs `decisions.md` and goes on with the apply; when it still does not apply the files are put back and the usual REBASE / MERGED path follows.
   - **Not clean**: set the task back to `ticketed`, note `rebase: base moved`, and append history. A builder then
     rebuilds it on a fresh worktree, starting from the kept patch (`Restore-TaskPatch.ps1`). The old worktree stays
     listed for the owner.
3. Run the task's checks against the main tree (`Integrate-Patch.ps1` does it through `Invoke-Grader.ps1`): the builder's recorded check (`artifacts.check`: its clause tests plus the existing tests it chose as the change's impact), and the author's grader too when the row has one. Both run into one log, and either failing is a FAIL. A row with neither cannot be verified on main and is bounced (owner rulings IN-20261002160453-ce2a, IN-20261002160643-741d).
   - **PASS**: set state `integrated`, append history, then commit exactly the paths the patch touches (`git add -A`
     and `git commit -- <paths>`; other dirty or staged files stay out), message `<task>: <title>`. A failed commit is
     logged in `decisions.md` and the work stays uncommitted; the task stays `integrated`. `-NoCommit` turns this off.
   - **FAIL**: before reversing, decide whether the grader or the code is wrong. Then reverse the patch
     (`git apply -R`, followed by `git update-index -q --refresh`).
     - **SUSPECT** (grader defect): every clause red on main passed in the builder's worktree log
       (`<task>.grader.wt.txt`) under the same grader (`GRADER sha`), and main held exactly the worktree's content for
       the patch's files. A clause like that can't pass after any `git apply` (file times, tree-local state). The task
       goes to `planned` with the patch kept, and a line goes to `owner\questions.md`. An author writes a portable
       grader; the builder then lays the kept patch down and re-verifies, and does not rebuild.
     - **REVERSED** (code defect, or not provably the grader): the task goes to `ticketed`, and the note says which
       test failed (a clause that also failed in the worktree, a changed grader, differing content, or a gone
       worktree). The patch stays as the builder's starting point.
4. A `mockup` task that is `built` moves to `integrated` with no tree change. Its `gate` task then waits for the owner.

### B. Group suites (tiered, 2026-10-05 priority-focus-design 3.3)

Testing has three tiers, and only Tier 1 spends your units on every patch:

| Tier | When | What |
|---|---|---|
| 1 Patch | each integration (step A) | builder check + grader on main, unchanged |
| 2 Full | nightly 01:00 (scheduled task) and ONCE when the focus set's last non-fix row integrates | every test suite, in a snapshot; no graders (they run at integration; owner ruling IN-20261005230119-9a3d) |
| 3 Retest | after fix tasks integrate | only the failed tests this group owns, plus the fix rows' impact checks |

A Tier 2 run takes 1.5-2 h, and the old rule ran one after every fix round, up to three per group; the clock check
alone cost a unit every 10 minutes. The nightly is a Windows scheduled task now (`Register-NightlySuite.ps1`, the owner
registers it once), so you never spend a unit on a clock.

**Run definition, once per group.** Before the group's first Tier 2 run, write `.streams\suites\<group>.run.json`
(shape in `Start-SuiteRun.ps1`'s header): `copyIgnored` (for example `.env`, `.env.local`, `tests\Tests.E2E\.auth`),
`setup` (`npm ci --prefix tests\Tests.E2E`, the solution build), `legs` in order (Tests.Unit, Tests.Web, Tests.Browser,
Architecture as `kind: dotnet` with `--logger trx --results-directory {runDir}\<leg>`; Playwright as `kind: playwright`
with `PLAYWRIGHT_JSON_OUTPUT_NAME={runDir}\Playwright\results.json` and `--reporter=json,line`), no `graders` key (a Tier 2 run never runs graders), and
`after` (redeploy web from main: `docker compose -f compose.yaml up -d --build --wait web`, `workDir: repo`). The
snapshot never gets `node_modules`, so `setup` runs `npm ci`.

**Deploy the snapshot before the legs.** Playwright drives the running compose web (`SM_WEB_URL`, else
`Speedy__Web__ExternalUrl` in `.env.local`, else `http://localhost:5310`), not the snapshot, so a run whose web was deployed
from an older tree accepts browser evidence for code it never ran (run-G4-5, kit item IN-20261011022936-074c). End
`setup` with two steps that run in the snapshot (no `workDir`): `web` = `docker compose -f compose.yaml up -d --build --wait web`
(the project name is fixed in `compose.yaml`, so it replaces the same containers with images built from the snapshot's
files) and `web-image` = `docker compose -f compose.yaml images web`, whose log `setup.web-image.txt` records what was
deployed. `after` still redeploys web from main: the snapshot is reaped later and its `.auth` bind mount with it. The
after steps run last, behind the flaky screen, which re-runs on the same snapshot; a Tier 3 retest runs them too. A
`retestSetup` you write must end with the same two steps when the group has a Playwright leg.

**Visual variables for the Playwright leg.** `tests\Tests.E2E\tests\visual\crewchief-look.spec.ts` refuses each of its
two tests when its variable is missing (`requireEnv`), and its describe is serial, so a refused first test SKIPS the
live-view test after it. Set them in the leg's own command: `SM_VISUAL_OUT` = `<repo>\.streams\logs\<group>.suites.{run}.visual`,
`SM_LIVE_VIEW_OUT` = `<repo>\.streams\logs\<group>.suites.{run}.live-view`, and `SM_MOCKUP_HOME` only when the owner's
environment already sets it (nothing in the tree records the mockup folder, so never invent one). When it is unset, the
first test fails on its named precondition: record that once in `.streams\owner\questions.md` as an environment gap,
never a fix task (kit item IN-20261004201117-351d).

**The completion run.** When every `code`, `docs` and `mockup` row of the focus set is `integrated` (EXCEPT a row whose
`dependsOn` names the group's integration task: it is built from the green run, planner ruling IN-20260930190044-8bf9),
run `Start-SuiteRun.ps1 -Repo <repo> -Session <you> -Group <group> -Reason complete`. It takes the snapshot
(`New-SuiteSnapshot.ps1`), moves the integration task to `building`, records `.streams\suites\runs\run-<group>-<n>.json`
and starts the legs DETACHED (`Invoke-SuiteLegs.ps1`, every command through `Invoke-IntegratorRun.ps1`, which beats your
lock). `RUN-BUSY` = a run is still going; `LOCK-HELD` = not your lock. A run record whose process is gone (a reboot, a
killed unit) is marked `abandoned` and printed `ABANDONED <run>`, so it never blocks the next run. A nightly that finds
your lock live files you an inbox item `Start the nightly Tier 2 run ...`: run the command it names, with `-Reason nightly`.

While the legs run, keep cycling (inbox, step A: applies go on, the run has its own snapshot). Refresh your lock with
`Enter-Integrator.ps1` at least every 10 minutes between commands. When the record says `done`, the legs script has
already, with no tokens:
1. exported per-test results (`Export-SuiteResults.ps1`: `runs\<run>.results.json`, trx and Playwright json);
2. re-run the failed set once on the SAME snapshot (`Invoke-Retest.ps1 -Mode flaky`): a test that passes there is a
   flaky candidate in `.streams\suites\flaky.json`, no fix task; two more failures in the next five Tier 2 runs
   promote it to a failure;
3. attributed every failure (`Register-SuiteFailures.ps1`, `runs\<run>.attribution.json`) by the owning row's write
   set, the rule this step always used (groups close in board order, owner ruling IN-20261001193348-5979):
   - this group or an earlier group owns it: a fix task in THIS group (`origin: integration`, write set = the failing
     file, one task per file; the builder widens it with `-AddWriteSet`). It blocks this close.
   - only a LATER group owns it: `.streams\suites\known-failures.<later>.json`, NO fix task now; it becomes a fix task
     at that group's activation. It does not block this close.
   - no row owns it: one `stream-plan` inbox item; the planner picks the earliest group whose feature the test covers.

Read `runs\<run>.attribution.json` and the run's decisions line; you only act on what the scripts could not decide.
Other end states of a run record: `setup-failed` (a setup step failed: fix the environment or the run definition, then a
`-Reason manual` run), `lock-lost` (another session took your lock mid-run: re-enter and start a new run), `abandoned`
(its process died: start a new run), and an `attributionError` field (export, flaky screen or attribution threw: the
close rule reads `NOT-ATTRIBUTED`; fix the cause and run `Register-SuiteFailures.ps1 -Run <run>` yourself).

**Tier 3.** When a fix task lands, run `Invoke-Retest.ps1 -Repo <repo> -Session <you> -Group <group> -Mode fix`.
It takes a NEW snapshot, runs the run definition's `retestSetup` steps (or its `setup` steps: npm ci, the build), and
runs only the `fix` failures that no retest has passed yet AND whose current fix row landed since the last retest that
ran them, with `--filter "FullyQualifiedName~<Class.Method>"` per dotnet project (never `=`, which breaks on DataRow
names) and the failed Playwright files with an escaped `--grep` anchored at the title plus any `@tags`, plus every fix
row's `artifacts.check`. `RETEST-NOTHING ... no fix landed` = nothing to do until the next fix lands; do not re-run it
on a timer. A retested failure that still fails files the next fix attempt itself (`REFIX <test> <row>`, chained after
the last one) until it has failed three retests. `RUN-BUSY` = a Tier 2 run is going: retest after it ends. Once its legs
end (or its setup fails), it runs the run definition's `after` steps, so web goes back to main.
`setup-failed` counts as no retest. A late gate-fail fix (`Add-Tasks` REOPENED) also needs a Tier 3, not a new Tier 2.

**Close rule.** `Test-GroupClose.ps1 -Repo <repo> -Group <group> -Session <you>` replaces "green, or blocked after three
full runs". `CLOSE-OK` = every non-fix row integrated; the latest Tier 2 run started after the last such patch and is
attributed; every patch after it is a fix with a passing Tier 3; every `fix` failure passed a Tier 3; no fix row open;
gates passed; no leg crashed. `CLOSE-REFUSED <reason>` lines name what is missing (`TIER2-STALE` / `NON-FIX-AFTER-RUN`:
a non-fix row landed after the run, so the next nightly or a `-Reason manual` run is needed; `LEG-CRASHED`: a leg left no
results, so that run covered nothing there and a new Tier 2 run is needed). `CLOSE-BLOCKED` (exit 3) = the same test
failed three Tier 3 fix attempts: the script sets the group `blocked` and asks the owner in `owner\questions.md`; stop
working that group. The owner unblocks with `Test-GroupClose.ps1 -Repo <repo> -Group <group> -Unblock` (restores the
group's state, restarts the strike count, files the next fix attempt).

### C. Close a group

On `CLOSE-OK`, run `Close-Group.ps1 -Repo <repo> -Session <you> -Group <group>` (v0.13; never close by hand). It re-runs
the close rule and, in one locked write, sets the integration task and every integrated row of the group `done`, taking
the rows by their `group` field plus the group set, never by id prefix: a row a plan revision moved into the group keeps
its old prefix (G1.T24 and G1.T25 in G3 were left `integrated` by a hand close on 2026-10-05). It sets the group `closed`,
logs the close in `.streams\decisions.md` and lists the rows' worktrees in `.streams\owner\worktrees.md` as "ready to
remove" (the owner validates removal; this skill never removes a worktree). `NOT-CLOSED` (exit 1) = the rule did not
pass; `ROW-STATE` (exit 2) = a row is neither integrated nor done; both write nothing. On a group that is already
`closed` it repairs instead: integrated rows go `done` (`REPAIRED`), any other state is reported (`ANOMALY`).

When the group's integration task has a grader (`artifacts.grader`), `Close-Group.ps1` runs it on the main tree after
`CLOSE-OK` and before the write (`Invoke-Grader.ps1 -Task <it> -Root <repo> -Label close`, v0.14). It checks the close-out
work the integration ticket asks for, such as an evidence matrix or a saved `CLOSE-OK` record, which the close rule does
not see. A non-zero exit is `NOT-CLOSED` (exit 1, log `.streams\logs\<it>.grader.close.txt`) and nothing is written: do
that work, then run `Close-Group.ps1` again. `-DryRun` names the grader (`GRADER <it> would run`) without running it.

Then, in the same cycle, activate the next group: `Activate-Group.ps1 -Repo <repo> -Session <you> -Group <next focus group>`
(2026-10-05 priority-focus-design 3.2; no tokens). It sends every ticketed row of the new focus set whose write set, or
whose dependencies' write sets, changed on main since it was ticketed back to an author (`STALE:` note, `Revise-Task.ps1
-Release planned`; a claimed row is skipped and reported), turns the group's known failures into fix tasks, writes its
gates to the owner queue, and records `.streams\plans\<group>.activation.json`. `ALREADY-ACTIVE` = done before.

### D. Idle

When 0 to C have nothing to do, end the cycle with ScheduleWakeup at 600 s (noop). The same 600 s ceiling applies to
every other cycle too, including one that is only waiting on a running suite or drain (see Inbox cadence under 0).
There is no clock check: the nightly is the scheduled task's, not yours. When every group is `closed`, stop the loop.

## Gates (owner, no prompt)

- Each `gate` task is listed in `.streams\owner\gates.md` with what to look at and where (a link or route).
- The owner runs `/stream-integrate gate <task> pass|fail "<note>"`.
  - **pass**: sets the gate `done`.
  - **fail**: turns the note into a fix task (the write set comes from the mockup or code task the gate follows),
    added with `Add-Tasks.ps1 -Role integrate`. That task has usually landed, so the fix is chained after it. If the
    group's integration task is already `done`, `Add-Tasks.ps1` reopens it (`ticketed`), and a `closed` group goes back to
    `integrating`. A Tier 3 retest (`Invoke-Retest.ps1 -Mode fix`) then runs after the fix lands, before the group can close.
- A gate never stalls other tasks, including the suites. It only holds the group's close.

## Rules

- The only skill that writes the main tree, and it writes only by applying verified patches or reversing its own apply.
- Writes the main tree, `.streams\logs\`, `.streams\owner\`, `.streams\decisions.md`, `.streams\integrator.lock`, and
  through the lock task states, history and new fix tasks. It appends to `.streams\inbox\` files, never editing or
  deleting a line.
- Never edits a patch, a ticket or a grader. Never resolves a conflict by hand.
- Never runs two suites at once. A suite runs in its snapshot, so applying a patch to main while it runs is allowed.
- Never redirects a command's output into the repo. An `errs.txt` sat untracked in the main tree root on 2026-09-29
  holding one line of git stderr from an ad-hoc `2> errs.txt`, owned by nobody and read by nobody. A log goes under
  `.streams\logs\` or into the session scratchpad. The watchdog now prints a `JUNK` note for anything left in the root.
- Commits and pushes only as the machine profile's `## Git policy` row for the repo allows (`Commit`, `Push`).
  `Integrate-Patch.ps1` reads that row itself, because git-guard sees only command text and never the git a script
  runs. A missing row, a `no`, or an unreadable profile prints `COMMIT SKIPPED` or `PUSH SKIPPED`, logs it in
  `decisions.md`, and never blocks integration. A push goes to the one stream ref (`-PushRef`, default
  `refs/heads/users/agenewe/stream-sync`).
- Commits only an integrated patch's own paths (step A3). Never amends, never force-pushes, never branches, never stashes,
  never removes a worktree.

## Scripts (in `${CLAUDE_SKILL_DIR}\..\stream-kit\scripts\`)

- Every cycle starts with `Enter-Integrator.ps1 -Session <id>`. Exit 5 = another integrator holds the lock: print status only.
- 0: `Get-InboxItems.ps1 -Skill stream-integrate -Open` lists the open items, oldest first;
  `Set-InboxItem.ps1 -Skill stream-integrate -Id <id> -By <session> -Status taken|done|declined|forwarded [-Note] [-ForwardTo]`.
- A: `Integrate-Patch.ps1 -Session <id>` (repeat until `NONE`). It prints `INTEGRATED` + `COMMITTED` (after a `STRAY-EMPTY` line when it cleared empty stray files), `BASE-STALE`, `REBASE`, `SUSPECT` or `REVERSED`.
- B: `Start-SuiteRun.ps1 -Group <g> -Reason complete|manual|nightly`, `Invoke-Retest.ps1 -Group <g> -Mode fix`, `Test-GroupClose.ps1 -Group <g>`;
  read `.streams\suites\runs\<run>.attribution.json`. Hand-made fix tasks (an unowned failure the planner assigned, a gate fail) go
  through `Add-Tasks.ps1 -Role integrate -File .streams\plans\<group>.fix-<run>.json`. The same file can set
  the group `state` (`integrating`, `blocked`, `closed`) through its `groups` list.
- Integration and gate tasks: `Update-Task.ps1 -Role integrate -To building|done`.
- C: `Close-Group.ps1 -Group <g>` on `CLOSE-OK`, then `Activate-Group.ps1 -Group <next focus group>` right after the close.
