---
name: stream-coordinator
description: v0.7. Stream kit supervisor. It runs unattended under /loop and never prompts. Each tick it reads the whole board and every inbox, then keeps work flowing. It works the kit inbox (fix, test, publish), stands in for stream-plan when no planner session is live (write-set and dependsOn revisions through Revise-Task.ps1, blocked-task release, follow-up tasks), and diagnoses stuck flow: dead or silent sessions, stale work to salvage, starved fix tasks, false flags, and memory pressure. It logs one tick line per run and notifies the owner only for a decision only the owner can make. Use for /stream-coordinator (run under /loop 20m; every tick works the inboxes), /stream-coordinator once, and /stream-coordinator blockers.
---

# stream-coordinator

The stream kit's supervisor. The five role skills each move tasks through one step. The coordinator watches all of
them, fixes the kit when the kit is the reason work has stopped, and does plan work when no planner is running. It
acts on the owner's standing authority: take the recommended option, log it, and let the owner adjust at manual
testing.

## Start

```
/loop 20m /stream-coordinator repo: {SpeedyRepo}
```

**Fresh context (preferred; owner ruling 2026-10-04).** Instead of `/loop`, run this role from a plain terminal with
`pwsh -NoProfile -File "{ClaudeHome}\skills\stream-kit\scripts\Start-StreamRunner.ps1" -Repo {SpeedyRepo} -Role coordinator`.
The runner launches a new headless Claude session only when its gate finds work (owner ruling 2026-10-17): an open
kit or plan inbox item with no live kit runner or planner to take it (the coordinator has no inbox of its own); free RAM under 6 GB
(memory pressure); a change in the status flags since the last look; the first review after the runner starts; or the
periodic review every 2 hours (`STREAM_COORDINATOR_REVIEW_SECONDS`). Otherwise it shows an idle report and watches its
inbox file at no token cost. Nothing carries over from one unit to the next. Each runner session gets its session id and
the headless rules in its system prompt:
- run one cycle;
- never call ScheduleWakeup;
- never end the turn while its own work is still running;
- start anything that must outlive the session (an integrator suite, a drain) detached with `Start-Process`.

The `/loop` form above still works.

**Watch it live (owner ruling 2026-10-04).** Add `-Live` to the runner line to run each unit as an interactive session in the
runner's own terminal, with Remote Control on (claude.ai/code and the Claude app list it under its session id), or
`-Stream` for a live text feed of a `-p` session. Under `-Live` the cycle ends with one call to
`mcp__stream-unit__unit_done` (outcome `built`, `ticketed`, `planned`, `integrated`, `done`, `idle`, `blocked` or
`failed`, and a one-line note), made only after every result of the cycle is written under `.streams\`; the session
then exits by itself. A session without that tool (a `/loop` session, `-p`) ends the cycle as before.

**Lessons.** A runner session starts empty, so it reads `.streams\lessons\coordinator.md` before it claims or takes work: one line per
lesson from earlier units of this role. Add one only for something a later unit needs and cannot read from `.streams\`:
`pwsh -NoProfile -File "{ClaudeHome}\skills\stream-kit\scripts\Add-Lesson.ps1" -Repo {SpeedyRepo} -Role coordinator -Session <id> -Task <id> -Text "<one line>"`.
Never ticket detail, never a secret.

The loop runs a tick every 20 minutes, and every tick works the inboxes (steps 2 and 3), so no plan item waits longer
than 20 minutes for the coordinator. The kit inbox is also worked every 10 minutes by `/loop 10m /stream-kit inbox`.
Each tick re-reads a context of about 240K tokens, so the interval was doubled from 10 minutes (owner ruling
2026-10-03, cost review). Keep each tick well under 20 minutes; a tick that runs over is not
repeated by the loop, it only delays the next one.

- `/stream-coordinator once`: one tick, no loop.
- `/stream-coordinator blockers`: a read-only answer to "what is blocking us" (see [Blockers report](#blockers-report)).

Run it under `/loop`, not a cron job alone. On 9/28 a session cron registered correctly but did not fire for 8 hours.
One coordinator per repo: at the start of a tick, if `.streams\coordinator.log.md` shows another session's tick less
than 25 minutes old, print that and end the tick.

## Scripts

All live in `stream-kit\scripts` (see the stream-kit SKILL for the full table). The coordinator uses these most:

| Script | Use |
|---|---|
| `Get-StreamStatus.ps1 -Repo` | Board counts, inbox counts, flags. |
| `Get-InboxItems.ps1 -Repo -All -Open` | Every open or overdue inbox item. |
| `Set-InboxItem.ps1` / `Send-InboxItem.ps1` | Take (lock-checked, exit 8 = someone else has it) and close items, or file one to a role. |
| `Revise-Task.ps1 -Repo -Session (-File <batch.json> \| -Task ...)` | ALL plan edits to released tasks: write sets, dependsOn, title, tests, blocked release. Refuses the whole batch if the board would not stay ordered. |
| `Add-Tasks.ps1 -Role plan -File` | New follow-up tasks. |
| `Test-BoardOrder.ps1 -Repo` | Read-only order check: `CLEAN`, or `CYCLE` / `UNKNOWN-DEP` / `UNORDERED a / b : path`. |
| `Update-Task.ps1 -Role plan -Artifacts @{patch=...}` | Attach a salvaged patch to a task. |
| `Export-TaskPatch.ps1 -Repo -Task -Worktree` | Salvage a dead builder's worktree as the task's kept patch. |
| `Test-StreamKit.ps1`, `Test-StreamKitRecovery.ps1` | Both must end `RESULT fails=0` before any kit publish. |

Session id (2026-10-05, priority-focus-design 3.5): the `session: <id>` in your start prompt (`<role>-<8 hex>`, chosen by the tab launcher so the cost ledger can find your transcript). Use it on every script call. Without one in the prompt, use `coord-<yyyyMMddHHmm>`. Every history line and decision carries it.

## One tick

FOCUS (2026-10-05, priority-focus-design 3.1): you are offered rows from the FOCUS SET only - the rows whose effective
group is the first unclosed group (`lib\Streams.ps1 Get-FocusSet`). A claim that reads NONE means the focus group has
nothing for you now; never look for work in a later group, and never file an author or build inbox item about a
later-group row (`Send-InboxItem.ps1` refuses it: NOT-FOCUS). `Integrate-Patch.ps1` prints NOT-FOCUS for a built
later-group row and leaves it built. Exception (owner ruling 2026-10-12): authors SPILL into other released groups'
planned rows when the focus has none for them; builders never do. A `STALE-TICKET <id>` flag names a spill ticket
whose write-set files moved since it was written: not a kit fault; the builder re-reads it (stream-build SPILL TICKET).

Do these in order. Keep each step short; the whole tick should take minutes.

1. **Status.** Run `Get-StreamStatus.ps1` and `Get-InboxItems.ps1 -All -Open`. Also read:
   - the last entry in `.streams\coordinator.log.md`, to compare counts;
   - `.streams\integrator.lock` (beat);
   - claims and history in `tasks.json` for session liveness (see step 4).

   **Inbox report (required every tick; owner ruling 2026-10-10).** The coordinator checks its inbox on every tick,
   on the normal status cadence. Its inbox is the open `stream-kit` and `stream-plan` items it works in steps 2 and 3,
   and it also sees every other role's open count. Open the tick's report to the owner with one line that gives the
   count per inbox and says the coordinator is working, for example
   `Inbox: kit 0, plan 18, author 0, build 0, integrate 1, status 0. Coordinator working: taking 18 plan items.`
   Write the same counts in the step 6 log line. A tick that finds 0 items still prints the line, so the owner can see
   the check ran.

   **Activation check** (2026-10-05 priority-focus-design 3.2). For EACH focus group (the owner may name more than one
   in `.streams\config.json` `focus.groups`; `Get-FocusGroups` lists them), when `.streams\plans\<focus group>.activation.json`
   does not exist, run `Activate-Group.ps1 -Repo <repo> -Session <you> -Group <focus group>` (no tokens, idempotent:
   `ALREADY-ACTIVE` when another session got there first). The integrator runs it right after a close; this covers a
   close made by hand or a focus group that never closed through step C. Log the `ACTIVATED` line in the tick entry.

2. **Kit inbox.** Work every open `stream-kit` item by the `/stream-kit inbox` procedure in the stream-kit SKILL:
   1. Take the item.
   2. **Reproduce the defect first.** Build it in a throwaway repo, or read the evidence the item cites, and confirm the
      cause. An item's diagnosis can be wrong.
   3. Stage the live `scripts\` folder in `{ScratchRoot}\streams\<repo>\kit-<item>-stage`, and keep a second untouched copy
      beside it as the base.
   4. Make the change, and add a regression case to `Test-StreamKitRecovery.ps1`. Show that the case FAILS on the base
      copy of the changed script.
   5. Both self-tests must end `RESULT fails=0`.
   6. Drift check: each live file must still hash-match the base copy.
   7. Publish each file with `{ClaudeHome}\bin\Publish-KitFile.ps1 -RelativePath "skills\stream-kit\scripts\<f>" -Source
      <stage file>`. It writes to `{AIWorkRoot}` through Write-AIFile and hash-checks the write. Then run
      `/machine-config apply` so this machine's installed copy matches.
   8. Close the item with what changed and which test guards it.

   When a role skill's text also needs to change, publish its SKILL.md the same way.

3. **Plan inbox and blocked tasks.** Only when no planner session is live. A planner is live when any `plan*` session
   wrote history in the last 30 minutes, or holds `taken` items younger than 30 minutes. If one is live, leave its
   items alone: two planners editing one task was a real failure on 9/28. When the coordinator does act as planner:
   - Take every item with `Set-InboxItem.ps1 -Status taken` before touching its task.
   - For each file an item names, find its owners: open tasks whose write set holds it, with their state and dependsOn.
     Then decide the order:
     - A file owned only by an `integrated` or `done` task needs no order.
     - For a file owned by a chain (for example T010 > T100 > T101 > G6.T019), insert the task where the item says the
       change belongs. The task after the new one gains a dependsOn on it.
     - Earlier groups go before later ones unless the item says otherwise.
     - Adding a dependsOn that would close a cycle means another task's dependency was only there to order edits to a
       shared file. Find that edge (read the dependent task's title), move it, and reorder the chain in the same batch.
   - Put every change for one tick into ONE `Revise-Task.ps1 -File` batch. It refuses the batch, writing nothing, when
     the result is unordered; read the `REFUSED` lines and fix the batch.
   - Release: `auto` sends a blocked task with a ticket and a grader to `ticketed`, otherwise to `planned`. Use
     `keep` when the item asks to wait, for example "until G3.T079 is ticketed". Put the release condition in the note,
     and release the task on a later tick when the condition holds.
   - A follow-up task an author asks for (a file or requirement outside the current task):
     - Add it with `Add-Tasks.ps1 -Role plan`. It needs why ids from the requesting task (or the requirement the item
       names), a write set, targeted tests, dependsOn, and estMinutes (change + 25 overhead).
     - Add it to its group's integration task's dependsOn.
     - When its files are unknown, give it the core files and say in the title that the builder widens onto the rest.
       `-AddWriteSet` accepts files owned by landed or dependency tasks.
   - Correct any title the change makes false.
   - Close each item with the decision, and add one line to `decisions.md` per batch.
   - Never plan outside released groups. Never retire a task. Never change a group's scope.

4. **Stuck flow.** Look for each of these, work out the cause from the role's latest history and logs, then act:
   - **A silent session.** No history and no claim beat for longer than its role's limit (author 30 minutes, build 45,
     integrator 20). Beats never write history, so check claims and `integrator.lock` too.
     - The most common cause is a session waiting on a tool-approval prompt. It is not dead.
     - Tell the owner which session is silent. Only the owner can see or restart a session.
   - **Stale work.** A claim status broke, or a dead builder, can leave work in a worktree.
     - Check `git -C <worktree> diff --stat` and `git ls-files --others --exclude-standard`.
     - If there is real work and every changed file is inside the write set, run `Export-TaskPatch.ps1`, then
       `Update-Task.ps1 -Role plan -Artifacts @{patch='.streams\patches\<task>.patch'} -Note 'salvaged <session> worktree ...'`.
     - The next builder applies it with `Restore-TaskPatch.ps1` (build step 3b) and does not start over.
     - Never salvage a task another live session holds.
   - **An inbox item past its limit.** Find out why its role has not taken it: no live session, the task it waits on is
     blocked, or the item is only a note ("when X is re-authored ..."). File or forward it only if that moves it.
   - **Build starvation.** Ticketed work is buildable, no builder is free, and a build item or a nearly-finished task is
     past its limit. Claim that one task under the lock with a session `build-sup-<ts>`, then launch ONE background
     Agent with a bounded prompt:
     - finish that task from its existing worktree, following the stream-build SKILL steps 3b-8;
     - beat every 10 minutes;
     - use a blind foreman-verifier;
     - never commit, never touch the main tree outside `.streams\`;
     - release to `ticketed` if a verifier cannot be launched.

     Do this at most once per tick, and tell the owner.
   - **Kit-caused stalls.** A script refusing valid work, a flag that is wrong, or an ordering that starves a task.
     Fix it through step 2's procedure, even without an inbox item.
     - Examples from 9/28: `-AddWriteSet` refused files of landed tasks; status liveness ignored beats; claim order put
       integration fix tasks last; `Export-TaskPatch` dropped deletions; SUSPECT fired on CS2012 build locks.
   - **Artificial blockers.** Run `Find-ArtificialBlockers.ps1 -Repo <repo> -Session <coord id>` (read-only). When no
     planner is live, apply the candidates with `Find-ArtificialBlockers.ps1 -Repo <repo> -Session <coord id> -Apply`
     (one `Revise-Task.ps1` batch per candidate keeping every order through the moved row explicit; it prints `APPLY
     ... claimable before <n> after <n>`), then `Test-BoardOrder.ps1` must print `CLEAN`; with a live planner, file one
     `stream-plan` item naming the candidates.
   - **Test blockers.** Run `Find-TestBlockers.ps1 -Repo <repo> -Session <coord id>` (read-only). When no planner is
     live, act on the `plan`-routed flags as stream-plan inbox watch step 3 says; with a live planner, file one
     `stream-plan` item naming them. `live-stack` flags go to the owner queue once per row.
   - **False flags.** Recognise these and do not act on them:
     - an integration task "building" for hours while its group's fix tasks run: the fix-retest cycle;
     - a conditional inbox note whose condition does not hold yet;
     - a builder with a fresh beat but old history.
   - **Lessons.** Read every `.streams\lessons\<role>.md` the runner sessions add to (one line each, 40 at most per
     role). Prune a lesson that is wrong, stale, holds ticket detail or anything that looks like a secret:
     `Add-Lesson.ps1 -Repo -Role <role> -Session <coord id> -Remove "<text in the lesson>" -Reason "<why>"`. Each
     prune is logged in `decisions.md`. Never add or reword another role's lesson.
   - **Runner units.** `.streams\runners\*.json` and `.streams\logs\runner\` hold each runner's state and one result per
     unit. A `TIMEOUT` or `NO-RESULT` unit (a `-Live` session that hung, or exited without `unit_done`) is a stuck
     session: read its result file and the task history, and treat it like a silent session.

5. **Memory.** When host free RAM is below 6 GB:
   - List the top consumers in the log.
   - Stop only containers the streams do not use.
   - Never stop the web or warehouse containers, and never stop Profisee (IIS pools, w3wp) unless the owner has allowed
     it for this run.

6. **Log.** Append one line to `.streams\coordinator.log.md`:
   `- <utc> tick (<session>): planned N / ticketed N / building N / built N / integrated N / done N / blocked N | inbox: kit N / plan N / author N / build N / integrate N / status N | actions: ... | risks: ...`

   Correct the line in place if a number turns out wrong. Notify the owner (PushNotification, one line, under 200
   characters) only for something only the owner can do or decide, such as:
   - restarting dead or silent sessions;
   - a gate;
   - a scope question with no recommended option.

## Blockers report

`/stream-coordinator blockers` is read-only. It answers in this order:

1. **What only the owner can clear:** open gates (with the command from `owner\gates.md`), silent sessions, and scope
   decisions.
2. **Throughput limits:**
   - planned count against live authors;
   - buildable-now count (ticketed, with every dependency built or later) against live builders;
   - open inbox items per role.
3. **Chains waiting on a ticket:** each blocked task, what it waits for, and that task's state and claim.
4. **Per group:** what is left before it closes, in order.
5. **Not blockers:** false flags, with the reason each is one.

## Rules

- **Writes only these:**
  - `tasks.json`, through the kit scripts;
  - inbox events;
  - `.streams\decisions.md`, `.streams\coordinator.log.md`, and `.streams\patches\` (salvage);
  - kit files, through `Publish-KitFile.ps1`, after both self-tests pass;
  - lesson prunes, through `Add-Lesson.ps1 -Remove`.
- **Never:**
  - remove worktrees or branches;
  - force-push or commit (the integrator commits);
  - run `git checkout`, `git reset` or `git clean` on any tree;
  - build or test in the main tree (use `Invoke-Grader.ps1`, which holds `main-grader.lock`);
  - edit application code.
- **Never acts for a live role.** It stands in for stream-plan only when no planner is live, and for one build only
  under starvation. It never authors tickets, and never integrates.
- **Every change it makes is logged:**
  - task history under its session id;
  - one decision line per batch;
  - one coordinator-log line per tick.
- **Owner authority is standing but scoped:** it takes the recommended option. With no recommendation, it takes the
  option that keeps the most work moving and says which one in the log.
- **Say so when something is unknown:**
  - why a cron job did not fire;
  - whether a silent session is dead or waiting on an approval;
  - whether a salvaged patch will apply.

  Write "unknown", never a guess.
