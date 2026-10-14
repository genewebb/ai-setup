# Stream kit: how to use it

The stream kit builds work in parallel. Five skills each play one role in their own Claude Code session. They
coordinate only through `<repo>\.streams\tasks.json`, so no session waits on another session's conversation. Only the
planner asks you questions. Every other session runs unattended under `/loop` until its work runs out.

stream-integrate commits each patch as soon as its grader passes on the main tree, so history only ever holds verified
patches. Nothing else in the kit commits, and nothing creates branches or removes worktrees.

## The flow

```
/stream-plan  ──releases──▶  planned ──author──▶ ticketed ──build──▶ built ──integrate──▶ integrated ──group suites green + gates──▶ done
   (you)                                                                                    │
                                                                   suite failures ──▶ fix tasks (planned) ──▶ same path
```

1. **Plan** a group. You approve its review page and its tasks are released.
2. **Authors** turn each task into a ticket plus a grader that fails today for the stated reason.
3. **Builders** build each ticketed task in its own detached worktree and hand off a patch, which a blind verifier checks.
4. **The integrator** applies each patch to your main tree as soon as it is built. When the whole group is in, it runs
   the full suites once. Failures become fix tasks, followed by one more full run.
5. **You** pass the gates (your live looks). The group closes when the suites are green and every gate has passed.
6. **Status** republishes a live page every 15 minutes and frees work held by dead sessions.

The stages overlap: authors keep writing tickets while builders build the ones that are ready. Nothing waits for a
whole stage to finish, except the suite run, which waits for its own group.

## The correct order to open sessions

| # | Open | Session count | When |
|---|---|---|---|
| 1 | `/stream-plan` + start prompt | 1, only while planning | First, once per group or set of groups. Downstream sessions have nothing to do until a group is released. |
| 2 | `/loop 15m /stream-status repo: <repo>` | exactly 1 | Right after the first release. Delete the old MyLoop 15-minute cron at this point. |
| 3 | `/loop /stream-integrate repo: <repo>` | exactly 1 | Any time after release. It idles until something is built. |
| 4 | `/loop /stream-author repo: <repo>` | 1 to 3 | After release. |
| 5 | `/loop /stream-build repo: <repo>` | 1 to 4 | After release. They pick up tickets as soon as they appear. |

Steps 2 to 5 can be opened in any order, because each one idles safely. The only hard rule is **plan first**.

### How many of each

- **stream-plan: 1.** It is interactive, and two planners would ask you the same questions. Close it after approval and
  reopen it for the next group, `/stream-plan revise`, or an import.
- **stream-status: 1.** A second one only republishes the same page twice.
- **stream-integrate: exactly 1.** It is the only writer to your main tree, and a lock enforces that. A second session
  sees "HELD by ..." and only prints status, so opening one by accident is harmless.
- **stream-author: 1 to 3.** Claims are atomic, so authors never take the same task. More than about 3 rarely helps:
  authoring is faster than building, and a spare author just sleeps.
- **stream-build: 1 to 4.** Each builder works in its own worktree, with its own `bin`/`obj`, so builders never lock
  each other's builds. The real limits are:
  - **Ready work.** A group with 2 independent tasks keeps at most 2 builders busy. The status page shows how many
    tasks are ticketed and waiting.
  - **The machine.** Each builder runs a full `dotnet build` plus targeted tests, and some graders start a web host or a
    headless browser. Four at once is a sensible ceiling on one workstation.
  - **Shared resources.** A task whose grader starts the compose stack or uses port 5310 must not run beside another one
    that does. Keep those to one builder at a time.

A good default to start with is 1 status, 1 integrator, 1 author and 2 builders. Add a builder when the status page
says tasks are waiting for a builder, and add an author when builders are idle and tasks are still `planned`.

## Starting a new group

```
/stream-plan
repo:         {SpeedyRepo}
requirements: {SpeedyRepo}\docs\requirements\
groups:
  - G2 "Backup and Restore": FEAT-BACKUP-RESTORE-001
exclude:      (optional carve-outs)
```

The planner reads only the in-scope text. It asks questions in rounds of up to 4, each with a recommended option,
then publishes a review page. Reply `/stream-plan approve G2` and the running sessions pick the work up on their next
wake. There is no need to restart them.

Already-reviewed tickets skip planning: `/stream-plan import <group> <ticket paths>`.

## What needs you, and where

Everything waiting on you is under **Owner queue** on the status page, and is also stored in `<repo>\.streams\owner\`:

| File | What | Your action |
|---|---|---|
| `questions.md` | Questions a session answered with the recommended default | Nothing if the default is right. To override, tell the planner (`/stream-plan revise <group>`); the fix becomes a task. |
| `gates.md` | Live looks waiting for you, with the link | `/stream-integrate gate <task> pass "note"` or `... fail "what is wrong"` (in the integrator session). A fail becomes a fix task. |
| `worktrees.md` | Builder worktrees that are finished or abandoned | Confirm removal. The kit never removes a worktree. |

Integrated work is committed by the integrator. Anything integrated but still uncommitted (a failed commit) is listed on
the page.

## When something goes wrong

| You see | Meaning | Do |
|---|---|---|
| A task stuck in `building` with an old beat | Its builder session died | Nothing. Status frees it after 45 minutes and another builder retakes it. |
| `blocked` with a reason | The ticket or grader is wrong, a needed file belongs to another open task, or the work is already done (builders auto-accept every other choice) | `/stream-plan revise <group>`. |
| "N tasks waiting for build, no build session seen" | No builder is open | Open one. |
| A group `blocked` after 3 suite runs | Failures the fix loop could not clear | Read `.streams\owner\questions.md` and decide. |
| An integrator session says "HELD by ..." | Another integrator is running | Close the extra session. |

## Checks

- `/stream-kit test` runs the kit's end-to-end self-test against a throwaway repo (41 cases).
- `/stream-status once`, or `Get-StreamStatus.ps1 -Repo <repo>`, gives a snapshot at any time without changing
  anything.

## Stopping

Close any role session whenever you like. Its claimed task is freed by status after the timeout (author 30 minutes,
build 45 minutes, integrator 20 minutes), and nothing is lost: a builder's worktree stays on disk and is listed for
you. Each loop also stops by itself once every group is `closed`.
