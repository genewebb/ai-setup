---
name: stream-plan
description: v0.11. Stream kit skill 1 of 5, and the only interactive skill. The start prompt names the repo, where the requirements are, and exactly which group(s) of work to plan. Nothing outside that scope is planned. The skill reads the in-scope requirements, reads code only as needed, asks the owner requirement questions, cuts each group into tasks with disjoint write sets (or serialized by dependsOn), then publishes a record page and releases the tasks into .streams\tasks.json straight away, with no approval step, so the other stream skills can pick them up. The owner adjusts the implementation during manual testing. Use for /stream-plan, /stream-plan revise, /stream-plan import, /stream-plan status, and /stream-plan inbox (run under /loop: works the plan inbox every 10 minutes).
---

# stream-plan

Skill 1 of the stream kit. It primes the pump: no other stream skill has work until this one releases a group.
It is the ONLY stream skill that talks to the owner. Every other skill runs without prompts.

It works for any repo and any requirement set. It knows nothing about a project until the start prompt tells it.

## Start prompt (required)

A plan never starts from "all the requirements". The owner states the scope, and everything else is out of scope.

```
/stream-plan
repo:         {SpeedyRepo}
requirements: {SpeedyRepo}\docs\requirements\     (one or more folders or files)
groups:
  - G2 "Backup and Restore": FEAT-BACKUP-RESTORE-001
  - G3 "Steps": FEAT-STEPS-001 (REQ-STP-001..014 only)
exclude:      REQ-STP-015..020, anything marked DRAFT                 (optional)
```

- **repo**: the tree the tasks change. `.streams\` is created there.
- **requirements**: where the text lives. Only these paths are read as requirements.
- **groups**: one or more groups. Each gets an id, a name, and an explicit list of features, REQ ids, AC ids or sections.
  A group can hold part of a feature.
- **exclude**: optional carve-outs inside a named feature.

If a field is missing or ambiguous, the first AskUserQuestion round asks for it, and nothing is read until it is answered.
The resolved scope is written to `.streams\plans\<group>.scope.md` as the exact list of clause ids in scope, and it
heads the record page under **In scope** and **Out of scope (not planned)**.

## Commands

| Command | Does |
|---|---|
| `/stream-plan` + start prompt | Plan each named group: resolve the scope, read, question, cut, publish one record page per group, then release the group into `tasks.json` (state `planned`) at once. There is no approval step: the start prompt and the question answers are the owner's approval, and the owner adjusts the implementation during manual testing (owner decision 2026-09-27). |
| `/stream-plan revise <group>` | Re-open a released plan after the owner's edits: add, change or retire tasks that are still `planned`, re-publish the page and release the additions at once. |
| `/stream-plan import <group> <ticket paths>` | Bring already-reviewed tickets in as a released group, with no re-planning and no questions. Each ticket must already name its write set, its REQ/AC ids, its targeted tests and its dependencies. A ticket missing any of these is refused and listed. |
| `/stream-plan status` | Print each group's state and task counts, then the **Inbox status line** (see **Inbox**). Read-only, except that it starts work on any open item it finds. |
| `/stream-plan inbox` | Watch mode: work every open inbox item, then check again every 10 minutes (see **Inbox watch**). Run it under `/loop`. |

## Inbox

Other stream skills and the owner leave work for this skill in `<repo>\.streams\inbox\stream-plan.md`. The contract
(item format and states) is at the top of that file.

- **When**: at the start of every `/stream-plan` invocation (any command), before scope, questions or revise work.
- **Read** the open items with `Get-InboxItems.ps1 -Skill stream-plan -Open` (stream-kit scripts).
- **Handle** an open item here only when it fits this skill's write rules: new or changed tasks, scope, write sets,
  `dependsOn`, or a `revise` of a released group. Take it with `Set-InboxItem.ps1 -Status taken` before starting
  (exit 8 = someone else has it), then close it with `-Status done`, or `declined` with the reason.
- **Forward** any other item with `Set-InboxItem.ps1 -Status forwarded -ForwardTo <skill>`, which writes both lines.
- Inbox lines go only through `Set-InboxItem.ps1` and `Send-InboxItem.ps1`; never edit or delete an earlier line.
- **Report**: the release report (or the status output) lists every item still open, with its id and one line.
- **Inbox status line (owner ruling 2026-10-10).** Every status this skill gives the owner re-reads the inbox first
  (`Get-InboxItems.ps1 -Skill stream-plan -Open`; a status is any status, progress, ETA or "what is left" answer, the
  `/stream-plan status` output, a release report, and the end of every watch cycle). It then reports, in one line:
  `Inbox: <N> open (<ids, or counts by group>); working <ids being worked> | held <ids that wait, each with what it
  waits on> | none`. When N > 0, the session starts working the open items in that same turn (take, act, close), or
  says which ones it holds and why. It never reports a status without the line, and never says the inbox is empty
  without having read it in that turn.

## Inbox watch (every 10 minutes)

Start it once per repo, in its own session:

```
/loop /stream-plan inbox repo: {SpeedyRepo}
```

**Fresh context (preferred; owner ruling 2026-10-04).** Instead of `/loop`, run this role from a plain terminal with
`pwsh -NoProfile -File "{ClaudeHome}\skills\stream-kit\scripts\Start-StreamRunner.ps1" -Repo {SpeedyRepo} -Role plan`.
The runner launches a new headless Claude session only when `.streams\inbox\stream-plan.md` holds an actionable item
and no other planner is live (owner ruling 2026-10-17); otherwise it shows an idle report and watches the inbox file at
no token cost. Nothing carries over from one unit to the next. Each runner session gets its session id and the headless
rules in its system prompt:
- run one cycle;
- never call ScheduleWakeup;
- never end the turn while its own work is still running;
- start anything that must outlive the session (an integrator suite, a drain) detached with `Start-Process`.

The `/loop` form above still works. Session id (2026-10-05, priority-focus-design 3.5): the `session: <id>` in your start prompt (`<role>-<8 hex>`, chosen by the tab launcher so the cost ledger can find your transcript). Use it on every script call. Without one in the prompt, make one as before.

**Watch it live (owner ruling 2026-10-04).** Add `-Live` to the runner line to run each unit as an interactive session in the
runner's own terminal, with Remote Control on (claude.ai/code and the Claude app list it under its session id), or
`-Stream` for a live text feed of a `-p` session. Under `-Live` the cycle ends with one call to
`mcp__stream-unit__unit_done` (outcome `built`, `ticketed`, `planned`, `integrated`, `done`, `idle`, `blocked` or
`failed`, and a one-line note), made only after every result of the cycle is written under `.streams\`; the session
then exits by itself. A session without that tool (a `/loop` session, `-p`) ends the cycle as before.

**Lessons.** A runner session starts empty, so it reads `.streams\lessons\plan.md` before it claims or takes work: one line per
lesson from earlier units of this role. Add one only for something a later unit needs and cannot read from `.streams\`:
`pwsh -NoProfile -File "{ClaudeHome}\skills\stream-kit\scripts\Add-Lesson.ps1" -Repo {SpeedyRepo} -Role plan -Session <id> -Task <id> -Text "<one line>"`.
Never ticket detail, never a secret.

Each cycle:

1. Read the open items with `Get-InboxItems.ps1 -Skill stream-plan -Open`, and print the **Inbox status line**.
2. Work every open item as **Inbox** says: take, act through `Add-Tasks.ps1` / `Revise-Task.ps1`, then close or
   forward. After any board change, `Test-BoardOrder.ps1` must print `CLEAN`, and the pass gets one line in
   `decisions.md`.
3. Also re-check the rows that are `blocked` on a planner condition (for example "release once G3.T202 is ticketed").
   Release a row whose condition now holds; leave the others.
4. A decision that only the owner can make goes to the owner queue (`.streams\owner\questions.md`) with the default
   applied, the same as the auto-approve rule, as `<task> | question | default applied | why`. Only a decision with NO
   safe default is an escalation, written `ESCALATE <task> | question | why no default`. The status board counts
   escalations by that shape, not by a leading `- ` (kit item IN-20261004203020-5f5e). Watch mode never waits on AskUserQuestion. The owner works
   the queue in an interactive `/stream-plan` session.
5. Print the **Inbox status line** again, after the work (what is still open, what was closed this cycle). Then end
   the cycle with ScheduleWakeup at 600 s: `noop: true` when there were no open items, `noop: false` when anything
   was written. Pass the same `/loop` prompt back each time. **Backoff** (2026-10-05 priority-focus-design E4): after a
   noop cycle double the next delay (600, 1200), never above 1200 s (the 30-minute planner liveness rule); the first
   cycle that finds an open item goes back to 600 s. A runner does the same by itself and wakes on an inbox write.

Rules:
- **One watcher per repo.** Before its first cycle, the session writes `.streams\plan-watch.lock` (CreateNew,
  `{session, at, beat}`) and refreshes `beat` every cycle. A second session that finds a beat less than 20 minutes old
  prints the open items and stops. A stale lock is taken over, and the takeover is logged in `decisions.md`.
- **Hold limit.** An item this watcher takes is closed in the same cycle, or released with a `note` saying what it
  waits on, so a held item never blocks another planner.
- **Stop** the loop (ScheduleWakeup `stop: true`) when every group is `closed`, or when the owner says stop.
- An interactive `/stream-plan` session may still run beside the watcher. Both take items through `Set-InboxItem.ps1`,
  whose exit 8 stops a double take.

## Steps for each group

1. **Scope.** Resolve the group's list into clause ids. Record each feature's requirement status (READY, REVIEW, DRAFT).
   Only READY text is planned. An in-scope clause that is not READY becomes a question, not a task.
2. **Read the requirements**: every in-scope REQ and AC clause, plus the live amendments that touch those clauses.
   Out-of-scope text is read only when an in-scope clause refers to it, and it is never planned.
3. **Gap matrix.** For each in-scope AC clause, record one of `built+tested` / `built-untested` / `partial` /
   `contradicts-text` / `missing`, each with `file:line` evidence. Read code only to answer a clause. Do not survey the
   codebase.
4. **Questions.** Some things go to the owner through AskUserQuestion, in rounds of at most 4: anything the text leaves
   open, anything it contradicts, anything the code contradicts, and any in-scope clause that needs out-of-scope work.
   Every question carries a recommended option, listed first. Answers are logged in `.streams\decisions.md` (why and how).
5. **Cut tasks.**
   - One task per disjoint write set. Work that touches the same files is ONE task. No two open tasks share a file,
     except tasks on one `dependsOn` chain: a small shared edit (a registration line, a route list) may sit in two
     tasks when the later one depends, directly or transitively, on the earlier one. The later task builds on the
     earlier task's patch and the integrator applies them in dependency order, so they never race.
   - A UI change gets a mockup task first (ui-ux-pro-max, in the repo's standing layout). Its code task depends on it.
     The mockup is checked by the build verifier, not by an owner gate; the owner adjusts during manual testing.
   - Every group ends with one **integration task**: run the unit and integration suites once over the whole group,
     then retest. Failures become fix tasks, which `stream-integrate` adds itself.
   - Owner looks (a live click-through, for example) are **gate** tasks. A gate never stalls other tasks.
   - Estimate = the change plus one fixed overhead. The overhead covers the ticket, the build, the targeted tests and
     the verify. No suite time is included, because suites run once in the integration task.
6. **Order.** `dependsOn` per task, including dependencies across groups when several are planned together. Show the
   lanes (tasks that can run at the same time) and the critical path.
7. **Record page.** Publish one artifact per group:
   - scope in and out;
   - the gap matrix;
   - the task table (id, title, why = REQ/AC ids, write set, depends on, estimate, targeted tests, gate);
   - lanes and critical path;
   - decisions taken.
8. **Release** in the same turn, with no approval wait. Write every task to `tasks.json` as `planned`, set the group
   to `released` with the page link in `planPage`, and log it. Downstream skills see the work on their next wake.
   End the turn with the page link and the release report. Changes the owner wants later come through `revise`.
   The release report lists every inbox item still open (see **Inbox**).

## Rules

- Writes ONLY `tasks.json` (through the lock), `.streams\plans\<group>.*`, `.streams\decisions.md` and the review artifacts.
  Never code, tickets or tests.
- Never plans outside the stated scope. Work found out of scope goes on the record page under **Found, not planned**.
- Never releases a task whose write set overlaps another open task's, in any group, unless one depends on the other
  (directly or transitively). `Add-Tasks.ps1` enforces this.
- Every change to an already released task (write set, dependsOn, title, tests, releasing a blocked task) goes through
  `Revise-Task.ps1` as ONE batch per pass; it refuses a batch that would leave the board unordered. Never edit
  `tasks.json` by hand. After any revise pass, `Test-BoardOrder.ps1 -Repo <repo>` must print `CLEAN`.
- A row's `group` is revisable as well, and it is the planner's ONLY lever on the claim order: `Claim-Task.ps1`
  sorts fix-first, then group rank, then chain depth, so a short row that gates the FIRST group's close can sit
  almost last while it lives in a later group. Measured on G3.T149 on 2026-09-30: 8 estimated minutes, 103rd of the
  108 planned G3 rows, and the last thing standing between G1 and its close (owner ruling, kit item
  IN-20260930210139-4afa). Move it with `-Group <id>` or a `"group"` field in the batch, and move the integration
  edge in the SAME batch - the old group's integration task drops the row from `dependsOn`, the new group's adds it -
  or the batch is refused with `GROUP-WIRING`. The row KEEPS its id: G3.T149 in G1 is still G3.T149, because every
  ticket, grader, patch, verdict and inbox item already cites it. Also refused: a group id that is not on the board,
  a target group that is not released or integrating, a gate or integration task (its group is its identity), a row
  under a live claim, and either group whose integration task has already landed.
- Releases without an approval step (owner decision 2026-09-27): the start prompt and the answered questions are the
  approval. `import` releases the same way.
- A task's `why` must name in-scope REQ/AC ids. A task with no requirement behind it is a question for the owner.
- Fix tasks from integration failures do not come through this skill. `stream-integrate` adds them directly with
  `origin: integration` and the failing task's write set, so builders pick them up without a planner session.

## Shared contract: `.streams\tasks.json`

Location: `<repo>\.streams\tasks.json`, excluded through `.git\info\exclude`.

**Lock.**
- Every writer creates `tasks.json.lock` atomically (CreateNew) containing `{session, at}`.
- It then reads, changes and writes `tasks.json` (temp file plus rename) and deletes the lock. The lock is held for
  milliseconds.
- A lock older than 2 minutes is broken, and the break is logged in `decisions.md`.
- Readers never take the lock.

```json
{
  "version": 1,
  "repo": "{SpeedyRepo}",
  "requirements": ["{SpeedyRepo}\\docs\\requirements\\"],
  "groups": [
    { "id": "G2", "name": "Backup and Restore", "state": "planning|published|released|integrating|closed",
      "scope": { "include": ["FEAT-BACKUP-RESTORE-001"], "exclude": [], "clauses": ".streams\\plans\\G2.scope.md" },
      "origin": "plan|import", "planPage": "https://claude.ai/artifact/...", "releasedAt": null }
  ],
  "tasks": [
    { "id": "G2.T01", "group": "G2", "title": "...", "why": ["REQ-BAK-008", "AC-BAK-014"],
      "kind": "code|mockup|integration|gate|docs", "origin": "plan|import|integration",
      "writeSet": ["src/Cli/Verbs/BackupLocationSetupVerb.cs", "tests/Tests.Unit/BackupLocationSetup*.cs"],
      "tests": { "targeted": ["FullyQualifiedName~BackupLocationSetup"] },
      "dependsOn": [], "estMinutes": 45, "estBasis": "change 20 + overhead 25",
      "state": "planned", "claim": null,
      "artifacts": { "ticket": null, "grader": null, "patch": null, "verdict": null },
      "history": [ { "at": "2026-09-27T16:30", "by": "stream-plan", "to": "planned", "note": "released" } ] }
  ]
}
```

Task states (each later skill owns its own moves, designed skill by skill):
`planned` -> `ticketed` -> `building` -> `built` -> `integrated` -> `done`, plus `blocked` and `failed`. A `failed`
task goes back to `planned` with the reason in history. An imported task with a reviewed ticket and grader enters as
`ticketed`.

## Scripts (in `${CLAUDE_SKILL_DIR}\..\stream-kit\scripts\`)

- `Init-Streams.ps1 -Repo <repo> -Requirements <paths>`: run once before the first plan.
- Release and import: write the group and its tasks to `.streams\plans\<group>.release.json`, then run
  `Add-Tasks.ps1 -Role plan -Session <id> -File <that file>`. Exit 2 lists every refusal, and nothing is written.
- Import only: before release, run `Test-GraderPortability.ps1 -Grader <grader>` on every imported grader (for a shim,
  it also reads the grader the shim calls). A grader that is not `PORTABLE` compares file times, reads MyLoop row
  state, or leaves `-Since` unset, so it cannot pass after `git apply` on main, or it passes on stale evidence. Release
  that task with `artifacts.grader` set to null, so it enters `planned` and an author makes the grader portable. Log the
  flags per task in `decisions.md`. The ticket stays.
- Revise (inbox items, blocked tasks): `Revise-Task.ps1 -Repo <repo> -Session <id> -File <batch.json>` (format in the script's
  header). Put every task whose order must change in the same batch. Then `Test-BoardOrder.ps1 -Repo <repo>`.
- Retire (a blocked row withdrawn as superseded): `-Release retire -Note '<why>'` in the same batch that empties its
  write set and drops it from every open row's dependsOn (its integration task included). The row goes `done` with a
  `retired` record; the board counts it as `retired`, never as blocked or landed. Refused (`RETIRE-*`) for a row that is
  not blocked, holds a live claim, still owns a file or still has an open dependent. A row already `done` as a withdrawal (never integrated, no patch, not a gate or integration task) takes the same call and is marked retired in place (`RETIRED ... (backfill)`).
- Status: `Get-StreamStatus.ps1 -Repo <repo>`.
