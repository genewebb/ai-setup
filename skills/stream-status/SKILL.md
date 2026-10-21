---
name: stream-status
description: v0.8. Stream kit skill 5 of 5. It runs unattended every 15 minutes and never prompts, and works its own inbox at least every 10 minutes. It reads .streams\ and republishes one live status page per repo (groups, tasks by state, claims, the owner queue, ETA, open inbox items per role), then prints a 7-line terminal summary that opens with a heartbeat line (session working, own inbox count). It is also the watchdog: it breaks stale claims and a dead integrator lock so work flows again. Each cycle it works its own inbox (.streams\inbox\stream-status.md) within its write rules and scans all six role inboxes for stuck items. It replaces the MyLoop 15-minute update prompt. Use for /stream-status (run under /loop 15m), /stream-status once, and /stream-status inbox (run under /loop 10m: works its own inbox every 10 minutes).
---

# stream-status

Skill 5 of the stream kit. It is the owner's window onto the streams, and the watchdog that keeps them from stalling on
a dead session.

## Start

```
/loop 15m /stream-status repo: {SpeedyRepo}
/loop 10m /stream-status inbox repo: {SpeedyRepo}
```

**Fresh context (preferred; owner ruling 2026-10-04).** Instead of `/loop`, run this role from a plain terminal with
`pwsh -NoProfile -File "{ClaudeHome}\skills\stream-kit\scripts\Start-StreamRunner.ps1" -Repo {SpeedyRepo} -Role status`.
**The runner runs the tick itself, as scripts, with no model call (owner ruling 2026-10-17).** Every 15 minutes it runs
`Invoke-Watchdog`, `Get-StreamStatus`, `Build-StatusPage`, `Get-StreamCost` + `Build-CostPage`, `Build-PriorityPage`,
`Archive-TaskHistory` (first tick of each UTC day) and `Activate-Group` for a focus group without an activation record,
and prints one `STATUS-TICK` heartbeat line. A script that fails prints `TICK-FAILED` and files a stream-kit `bug` item
once. A Claude session is launched only when `.streams\inbox\stream-status.md` holds an open item, as
`/stream-status inbox`, so the model works only the inbox, never the page. Nothing carries over from one unit to the
next. Each runner session gets its session id and the headless rules in its system prompt:
- run one cycle;
- never call ScheduleWakeup;
- never end the turn while its own work is still running;
- start anything that must outlive the session (an integrator suite, a drain) detached with `Start-Process`.

The `/loop` form above still works. Session id (2026-10-05, priority-focus-design 3.5): the `session: <id>` in your start prompt (`<role>-<8 hex>`, chosen by the tab launcher so the cost ledger can find your transcript). Use it on every script call. Without one in the prompt, make one as before.

**Watch it live (owner ruling 2026-10-04).** Add `-Live` to the runner line to run each unit as an interactive session in the
runner's own terminal, with Remote Control only when the runner line adds -Remote (claude.ai/code and the Claude app then list it under its session id), or
`-Stream` for a live text feed of a `-p` session. Under `-Live` the cycle ends with one call to
`mcp__stream-unit__unit_done` (outcome `built`, `ticketed`, `planned`, `integrated`, `done`, `idle`, `blocked` or
`failed`, and a one-line note), made only after every result of the cycle is written under `.streams\`; the session
then exits by itself. A session without that tool (a `/loop` session, `-p`) ends the cycle as before.

**Lessons.** A runner session starts empty, so it reads `.streams\lessons\status.md` before it claims or takes work: one line per
lesson from earlier units of this role. Add one only for something a later unit needs and cannot read from `.streams\`:
`pwsh -NoProfile -File "{ClaudeHome}\skills\stream-kit\scripts\Add-Lesson.ps1" -Repo {SpeedyRepo} -Role status -Session <id> -Task <id> -Text "<one line>"`.
Never ticket detail, never a secret.

Start both in the same session. The full tick works the inbox too (step 3), so the second loop is only needed when
the tick runs less often than every 10 minutes. With the tick at 10 minutes or faster, start the first loop alone.

## Inbox watch (every 10 minutes)

The own inbox is worked at least every 10 minutes, whatever the tick interval. Items other roles send here (break
a claim, keep a claim, a page change) are time-sensitive: a request to break a dead claim that waits a full 15-minute
tick, plus the time it took to arrive, keeps a builder or author idle for most of an hour.

`/stream-status inbox repo: <repo>` runs ONLY step 3 (**Own inbox**), by the same contract and the same write rules:

1. Read the open items with `Get-InboxItems.ps1 -Skill stream-status -Open`.
2. Work every open item oldest first: take it, act within status's rules, then close it (`done` or `declined`) or
   forward it. Every item taken is closed in the same cycle.
3. Print the **heartbeat line** (see [Heartbeat](#heartbeat)), then one line per item handled: id, the action, the
   result. With no open item the heartbeat line is the whole output.

It does not run the watchdog, rebuild the page or print the other terminal lines; the next full tick does those and
reports the items this cycle closed. Like every status run it never prompts.

## Heartbeat

Owner ruling 2026-10-10: every status run, on its normal cadence (each full tick and each inbox watch), checks its
own inbox and reports how many items it holds and that the session is working. The owner must be able to tell a
working status session with an empty inbox from a dead one, and a silent run reads the same as a dead one.

- Count with `Get-InboxItems.ps1 -Skill stream-status -Open` (it prints `NONE` when there are none): run it at the
  start for the items **open at start**, count the items this run closed (`done`, `declined` or `forwarded`) as
  **handled**, and run it again at the end for the items **open now**. Read the file every run; never carry a count over from an earlier run.
- Print it as the FIRST line of the run's output, before anything else:
  `status <session> working | tick <local time> | own inbox: <N> open at start, <H> handled, <R> open now`.
  Local time is the host's local zone, never a UTC `Z` stamp.
- Print it even when nothing else happened. An inbox watch with no open item prints only this line.
- When `Get-InboxItems.ps1` throws or exits non-zero, print `status <session> working | tick <local time> | own
  inbox: UNREADABLE (<first error line>)` and carry on with the rest of the run. An unreadable own inbox is never
  reported as 0.
- Pass the same counts to the page as `-InboxLine "own inbox: <N> open at start, <H> handled, <R> open now"`, so the
  page shows the same numbers as the terminal.

## One tick

FOCUS (2026-10-05, priority-focus-design 3.1): you are offered rows from the FOCUS SET only - the rows whose effective
group is a focus group, plus every unlanded row they depend on, transitively (`lib\Streams.ps1 Get-FocusSet`; the board
flags a pulled row of an unlisted group as `FOCUS-PULL`, and its dependency flags are `DEP-REVIEW` and `DEP-MOVED`). A claim that reads NONE means the focus group has
nothing for you now; never look for work in a later group, and never file an author or build inbox item about a
later-group row (`Send-InboxItem.ps1` refuses it: NOT-FOCUS). `Integrate-Patch.ps1` prints NOT-FOCUS for a built
later-group row and leaves it built.

1. **Read** `tasks.json` without the lock, plus `.streams\owner\*.md`, `.streams\integrator.lock`, the newest
   `.streams\logs\`, and all six inboxes in `.streams\inbox\` (see [Inboxes](#inboxes)).
2. **Watchdog** (each write under the `tasks.json` lock). A claim is stale when its `beat` is older than its role's
   limit:

   | Role | Limit | Action |
   |---|---|---|
   | author | 30 min | Clear the claim. The task stays `planned`. |
   | build | 45 min | Clear the claim, set the task back to `ticketed`, and list the old worktree in `owner\worktrees.md`. |
   | integrator lock | 20 min | Delete `integrator.lock`. The next `/stream-integrate` session takes over. |
   | orphan (`building`, no claim) | 45 min | Set the task back to `ticketed` and list any worktree in `owner\worktrees.md`. |
   | inbox hold (`taken`) | that inbox's limit | Re-append the item's original `open` line, so it returns to the queue as first filed. |

   Every break appends task history (`by: stream-status`, with the stale beat) and one line in `.streams\decisions.md`.
   A claim whose beat is fresh is never touched, however long its task has run.

   An **orphan** is a task left `building` with no claim. Breaking claims does not reach it: a session can move a task
   to `building` without ever holding one (an integrator running a group's suites does exactly that), and a claimless
   task is invisible to every claim rule, so nothing else would free it. Its age runs from the move INTO `building`,
   not from the newest note stamped `building`, because a plan revise written while it sits there must not reset the
   clock or take the blame.

   An **inbox hold** is an item left `taken` by a session that has stopped working. A hold writes nothing after its
   `taken` line, so from the inbox file alone a session deep in one long item and a session that died an hour ago read
   the same. The board settles it: the holder's last write to `tasks.json`, from history or a claim beat, is the only
   evidence it is alive, and a holder that has written inside the limit keeps its hold however old the `taken` line is.
   Releasing re-appends the item's ORIGINAL `open` line with a fresh timestamp, so the next taker reads the same ask,
   task and evidence; the release itself is recorded in `decisions.md`. Taking an item over by hand is not a substitute:
   `IN-20260929001946-67a7` was manually rescued from a dead coordinator and the rescuer then died holding it too.
3. **Own inbox.** Work the open items in `.streams\inbox\stream-status.md`, oldest first, by its contract (the header
   at the top of the file is the source of truth):
   - Take it with `Set-InboxItem.ps1 -Status taken` (exit 8 = someone else has it), act, then close it with `-Status done` (with the result) or `declined` (with the reason).
   - Within status's rules, it can act on these:
     - **Break a claim.** Break it only if its beat is past the role limit. A fresh claim is declined: "beat N min,
       limit M".
     - **Keep a claim.** Add a note to the report that says not to break it early. The limits still apply.
     - **A page or report change.** Change what the page or the terminal lines show.
     - **A stale-state cleanup note.** Add a line to `owner\worktrees.md` or `decisions.md`.
   - Anything else goes to the inbox that owns it, with `Set-InboxItem.ps1 -Status forwarded -ForwardTo <skill>`,
     which writes the `forwarded` line here and the same id as a new `open` line there.
     - Anything else means work such as a task, ticket, grader, patch, commit, or kit-script change.
   - Finish every item you take within the tick, so a `taken` line never outlives a tick.
4. **Inbox scan** (report only). Across all six inboxes, find each item's status from its last line in each file.
   - Count the item as **open** when that status is `open`, `forwarded` with no `open` line for it in the target
     inbox yet, or `taken` older than the role limit.
   - A `forwarded` item that already has its `open` line in the target inbox counts only there.
   - Flag every item left **open or taken longer than its inbox role's claim limit**, measured from its last line.
     The flag gives the id, inbox, status, age and ask.

   | Inbox | Limit |
   |---|---|
   | stream-author | 30 min (author claim) |
   | stream-build | 45 min (build claim) |
   | stream-integrate | 20 min (integrator lock) |
   | stream-plan, stream-status, stream-kit | 30 min (kit default claim limit, `Test-ClaimLive`) |

5. **Flag** (report only):
   - a task `building` or `ticketed` past 2x its estimate;
   - a group `blocked`;
   - a role with claimable work but no live session seen in the last hour (for example "3 tasks ticketed, no builder
     running");
   - inbox items past their limit (step 4);
   - owner items waiting.
6. **Page.** Write `.streams\status.html` with `Build-StatusPage.ps1`. The script also copies the finished page to
   `{StatusPageDir}\status.html` when the machine profile sets that row, and to every path in
   `.streams\status-mirror.txt`. That mirror is the board's permanent address:
   - On a stream host the `StatusPageDir` row is the folder IIS serves, so the page has a fixed URL. That URL is in
     `.streams\status-url.txt` and does not change. With the row blank, `.streams\status.html` is the only copy.
   - Do NOT make a published artifact the board's link. An artifact is private to the account that published it, so
     the URL dies the moment the owner's account changes: two were lost that way on 2026-09-29 while the page itself
     was healthy and still served its bytes to the session that owned it. Publish one only when asked for a shareable
     copy, and never write its URL into `status-url.txt`.
   - A mirror that cannot be written is reported and does not fail the tick; the file in `.streams\` is the product.
   - The design lives in `status-page-head.html` beside the script. Edit that, not the renderer, to change the look.

   The page shows:
   - top tiles: the task total, one per state bucket (see [Ticketing](#ticketing)), the **pending owner-question
     count**, which links down to the list,
     and the **predicted finish for the whole board**. The question count is the one number on the page only the
     owner can move, so it sits above the fold rather than four sections down; a question answered in place with a
     leading `RESOLVED` token drops out of it.
   - the **Priority categories** table, one row per group in the owner's order, with a **predicted finish** per group
     beside the counts: the work left, the measured rate, and the date. See [Predicted finish](#predicted-finish).
   - each group with its state, a progress bar of task states, its predicted finish, and, under it, the work left,
     the measured rate, the earliest the dependency chain allows, and the downstream chain;
   - a task table: id, title, state, claim holder with beat age, estimate against elapsed, and the latest history note;
   - the **Owner queue**: open questions with the default applied, gates waiting (with their links), worktrees ready to
     remove, and uncommitted integrated work (the tasks integrated since the last commit, so the owner knows what a
     commit would hold);
   - **Inboxes**: the open item count per inbox (all six, zeros included), and one row per flagged item. The row gives
     the id, inbox, status, age against the limit, and the ask.
   - the watchdog actions, own-inbox actions and flags from this tick;
   - which role sessions have been seen (the latest claim or beat per role).
6b. **Cost.** Run `Get-StreamCost.ps1 -Repo <repo>` then `Build-CostPage.ps1 -Repo <repo> -Session <you>`. Both are
    scripts: no model call, no reading of the ledger. Print the `COST` line in the terminal summary. `NO-SUMMARY` or a
    thrown parse is a kit inbox item, never a stalled tick.
6c. **Priority.** Run `Build-PriorityPage.ps1 -Repo <repo> -Session <you>` (2026-10-05 priority-focus-design 3.4; a
    script, no model call). It writes `.streams\priority.html` (mirrored to `{StatusPageDir}\priority.html`, link in
    `.streams\priority-url.txt`) and records the focus group's milestones M1-M3 on its activation record. Print its
    `PRIORITY-PAGE` line in the terminal summary.
6d. **Archive, once a day** (the first tick after 00:00 UTC; E2): `Archive-TaskHistory.ps1 -Repo <repo> -Session <you>`.
    It moves the history of `done` rows older than 7 days to `.streams\archive\` (rows stay on the board) and rotates
    earlier months out of `decisions.md`. Print its `ARCHIVED` line.
7. **Terminal**: seven lines:
   - the heartbeat line (see [Heartbeat](#heartbeat)): session working, tick time, own inbox count at start, handled,
     and open now;
   - groups, each with its state and its predicted finish, then the board's;
   - counts by state bucket, `ticketing` included (see [Ticketing](#ticketing));
   - the owner queue size;
   - open inbox items per inbox, plus the count past their limit;
   - watchdog and own-inbox actions;
   - the page link, read verbatim from `.streams\status-url.txt`. Never print an artifact URL here.
8. When every group is `closed`, publish a final page and stop the loop.

## Ticketing

`ticketing` is the seventh bucket the page and the terminal count, and it is NOT a task state: nothing writes it to
`tasks.json` and no skill moves a task into it.

A task an author is writing the ticket for stays `planned` until the ticket and grader are released, so on the board
it read exactly like a row nobody had touched. That hid the whole authoring stage: four authors working and four
authors dead drew the same picture. `ticketing` is that stage, derived in `Get-StreamStatus.ps1` from the claim:

- state is `planned`, AND
- the claim's role is `author`, AND
- the claim's beat is inside the author limit (30 min), by `Test-ClaimLive`.

It is carved OUT of `planned`, never added beside it, so the tiles, the group bars and every total still add up to the
task count. A STALE author claim is deliberately excluded: the watchdog is about to clear it, and counting it would
report a dead session as work in progress, which is the exact failure this metric exists to expose.

Each task in the model carries `bucket` (the bucket the page draws) and `ticketing` (the boolean). A ticketing row's
elapsed time runs from `claim.at`, not from a state move, because it has not moved state at all. A ticketing row is
also out of the author demand count, so the board can no longer say "4 tasks waiting for author" about four rows that
are being written at that moment.

## Predicted finish

Every group carries a predicted finish date, and the board carries the latest of them. It is computed in
`Get-StreamStatus.ps1` and only rendered by the page, so the terminal line and the page can never disagree.

- **Work left** is the sum of the estimates on the group's tasks that are not `integrated` or `done`.
- **Rate** is measured from this board, never assumed: the estimated minutes that FIRST reached `integrated` or
  `done` inside a trailing window, divided by that window's LIVE hours. It therefore already carries the number of
  sessions actually running, the rework, the reaped worktrees and the short idle gaps. Nothing about capacity is
  entered by hand.
- **Outages are taken out.** An outage is a gap between two consecutive pieces of board activity (working-role
  history, claim `at`/`beat`, the integrator lock beat; `status-*` lines excluded) longer than 120 min; the part past
  120 min is subtracted from the window. The limit sits well above the 45 min build claim limit because beats are not
  recorded in history and a lightly staffed board lands about hourly. On 2026-10-01 a 16 h all-sessions-dead night priced G1 at
  18 h for 173 min of work. The silence from the last activity to now is never subtracted (the "no session seen"
  flag reports it), so the date reads as "if sessions keep running". The model carries `outageHours` and `liveHours`.
- **In focus order.** Only the focus group(s) (`Get-FocusGroups`) are worked; every other open group is frozen,
  so its own rate measures the freeze, not capacity (on 2026-10-08 G6 read 0.74 min/h and dated the board 14 Aug
  2027). A focus group is dated from its own history, capped at the **focus pool**: every focus row to go divided by
  the focus groups' combined tasks/h. A group newly added to the focus is dated from the pool, not from its frozen
  past. The groups after the focus are **queued**: each starts when the one before finishes (board order) and is
  priced at that focus rate times its own row count to go. The model carries `dating` (`focus`, `queued`, `closed`).
  The window starts at 24 h and widens (48, 72, 168 h) until it holds at least 3 completions:
  a 24 h window over one task prices a whole group off that task. Widening with few completions lowers the rate, so
  the error leans late.
- **Floor.** The date is held at or after `Get-UpChainMinutes` for the group: the longest chain of unlanded work it
  sits on top of, dependencies in other groups included. `Get-ChainMinutes` is the DOWNSTREAM chain and must never
  be used to date a group - on 2026-09-29 it read the same 4295 min for all six while G1 had 1065 min of work left.
- **No rate, no date.** A group with no completion in the widest window is reported undated, with the reason. It is
  also flagged, and the board date names it as not covered.
- **The board date is the last queued group's finish**: the focus groups run concurrently and the queued groups one
  after another, so the latest group date is that sequential finish. The board rate is the focus rate, never a sum of
  every group's own rate. A queued group behind an undated focus is undated and named.

## Inboxes

- One file per role in `.streams\inbox\`: `stream-plan.md`, `stream-author.md`, `stream-build.md`,
  `stream-integrate.md`, `stream-status.md` and `stream-kit.md`.
- Each file carries its contract at the top. Status acts only on `stream-status.md`, and only reads the other five.
- Item line: `- <id> | <utc> | <from> | open | request|bug | <task id or -> | <ask> | <evidence or ->`.
- Event line: `- <id> | <utc> | <by> | taken|done|declined|forwarded | <note>`.
- The status is the fourth field of the last line for that id in the file.
- Lines are append-only and go only through `Send-InboxItem.ps1` and `Set-InboxItem.ps1`, which lock the file.

## Rules

- Writes ONLY:
  - claim breaks, and the state rollback that goes with each, through the lock;
  - `integrator.lock` removal;
  - `.streams\status.html`, `.streams\status-url.txt`, `.streams\status-mirror.txt` and the mirror targets they name;
  - the page itself, plus `owner\worktrees.md` and `decisions.md` lines for its own actions;
  - appended event lines in `inbox\stream-status.md`;
  - one appended `open` line in another inbox for each item it forwards, and one for each dead hold the watchdog
    releases in any inbox.
- Never creates, re-plans or closes tasks. Never touches the main tree, a worktree, a patch, a ticket or a grader.
- Never removes a worktree.
- Never acts on another role's inbox item: it only counts and flags it. The one exception is the watchdog releasing a
  dead hold, which returns the item to its own inbox unchanged and decides nothing about the ask.

## Scripts (in `${CLAUDE_SKILL_DIR}\..\stream-kit\scripts\`)

- Step 2: `Invoke-Watchdog.ps1 -Session <id>`. It SALVAGES before it reaps: a tree whose task has not landed has its content exported and attached as the task patch first, and a tree whose work falls outside the write set is kept and reported as KEPT. Besides stale claims, the integrator lock, dead inbox holds and the
  worktree reaper, it sweeps the HOST temp folder and reports untracked junk left in the repo root. A `JUNK` or `WARN`
  note prints after the action lines and is not an action, so it never appears in `decisions.md`: carry it into the
  tick summary and file an inbox item if it is still there next cycle.
- Steps 5 to 7: `Get-StreamStatus.ps1` for the terminal lines, and `-Json` for the page model.
- Step 3: `Get-InboxItems.ps1 -Skill stream-status -Open`, then `Set-InboxItem.ps1 -Skill stream-status -Id <id> -By <session> -Status ...`.
- Step 4: `Get-InboxItems.ps1 -All -Json` lists every item in all six inboxes with its status, age and limit.
  `Get-StreamStatus.ps1` already counts open items per inbox (its `inbox:` line) and flags items past their limit.
- Step 6: `Build-StatusPage.ps1 -Repo <repo> -Session <id> -WatchdogLine "<line>" -InboxLine "<line>"` renders
  `.streams\status.html` from the `-Json` model and mirrors it to each path in `.streams\status-mirror.txt`. That is
  the whole page step; nothing else is needed for the link to update.
