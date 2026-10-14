---
name: stream-adhoc
description: v0.1. Stream kit ad-hoc role. One long interactive session per repo (addStreamTab -Role Adhoc) that takes the owner's ad-hoc change requests typed in its tab, mostly tweaks to existing UI and changes no group has picked up, and does every role's job for each one - requirements, mockups when the look or flow changes, owner approval of both, the code, one targeted test, a compile and that test on main, and the commit. It changes only finished work (closed groups); a request that belongs to an open group's future work becomes a requirement plus a stream-plan inbox item for that group, with no code. No suites run; the owner tests by hand. Use for /stream-adhoc repo: <repo>.
---

# stream-adhoc

The ad-hoc role. The other stream roles move planned tasks through one step each. This role takes one request from the
owner and carries it the whole way, from requirement to commit, in one interactive session.

Typical requests: a tweak to an existing screen, a wording or layout fix, or a small behavior change that no group's
plan includes.

## Start

```
addStreamTab -Role Adhoc -Repo {SpeedyRepo}
```

The tab runs `/stream-adhoc repo: {SpeedyRepo}`. It is a long interactive session, like Planner and Coordinator:
- the owner types requests in this tab, and only there; there is no ad-hoc inbox;
- one Adhoc tab per repo;
- the stream-compact mod compacts it as its context fills.

Session id: the `session: <id>` in the start prompt, otherwise `adhoc-<yyyyMMddHHmm>` from the session's start time.
Use it on every script call.

On start, read `.streams\lessons\adhoc.md` if it exists, then wait for a request. Do not poll, and do not start
work nobody asked for.

## Finished and future work

A group is finished when its `state` in `.streams\tasks.json` is `closed`. Open groups are released but not closed.
Read the group list at the start of every request, because groups close while the session runs.

Sort each request before any work:

| The request changes | What Adhoc does |
|---|---|
| Behavior that a closed group delivered, or code that no open task plans to add | Requirement, mockup if needed, approval, code, test, commit. |
| Behavior that an open group will deliver (its requirements are in the `why` ids of an open group's unfinished tasks, or the feature belongs to an open group) | Requirement only. Get it approved, then file a stream-plan inbox item that asks the planner to add or change a task in that group. No code. |
| Both | Split it. Do the finished part as above; send the future part to the planner. |

Show the owner how you sorted the request and ask them to confirm it (see [Questions](#questions)) before you write
anything.

**Shared files (owner ruling 2026-10-11, "edit, then tell the planner").** A file this change edits may also be in the
write set of an unfinished task (state `planned`, `ticketed`, `building` or `built`). Edit it anyway. After the commit,
file one stream-plan item per such task:

```
pwsh -NoProfile -File "{ClaudeHome}\skills\stream-kit\scripts\Send-InboxItem.ps1" -Repo <repo> -To stream-plan -From <session> -Kind request -Task <task> -Ask "<task>: adhoc <Id> (commit <sha>) changed <file>: <what changed>. The task's ticket or kept patch may need a rebase onto it." -Evidence ".streams\adhoc\<Id>.md"
```

Find these tasks by reading `tasks.json`: every task whose `writeSet` holds the file and whose state is one of those four.

## One request

Each request gets an id `ADHOC-<yyyyMMdd>-<n>`: the next free n for today in `.streams\adhoc\`. Keep the request
file `.streams\adhoc\<Id>.md` from the first step to the last:
- the request in the owner's words;
- the sort decision;
- the requirement ids;
- the mockup link;
- each approval, with the time;
- the files changed;
- the test;
- the commit.

1. **Sort.** Sort the request as above, and confirm with the owner.

2. **Requirements.** Load the `requirements-writing` skill and follow it.
   - The corpus is `docs\requirements` in the repo. On SMVMTR1 `{VaultDocsRoot}` is blank, so the repo copy is the
     corpus; on a machine where it is set, follow that skill's location rules.
   - Add or change the clauses the request needs: a requirement and its acceptance criteria.
   - Run `python tools\requirements\reqtools.py digest --write <artifact>` on each changed artifact, then
     `python tools\requirements\reqtools.py validate docs\requirements`. Both run in your worktree (step 4). Make the
     worktree before this step when the requirement files change.
   - Show the owner each clause in plain English with a before and after, then ask for approval. Write no code before
     the requirement is approved.

3. **Mockups**, only when the change alters what a screen looks like or how it is used.
   - Load the `ui-ux-pro-max` skill.
   - Keep the standing layout rules: the CrewChief master/detail layout for panels; the full-width layout for Steps and
     Workloads.
   - Measure every figure you write in the mockup notes with a probe. Never estimate one.
   - Publish the mockups as one artifact, give the owner the link, and ask for approval.
   - A text, behavior or data fix that does not change the look needs no mockup. Write "no mockup: <reason>" in the
     request file.

4. **Worktree.** Make your own worktree and work only there:
   - `git -C <repo> worktree add --detach {WorktreesRoot}\<repo name>\<Id> HEAD`
   - Never edit the main tree.

5. **Change.** Make the approved change. Follow the repo's conventions and the memory rules for this codebase.

6. **Test.** Write one test for what changed: a bUnit component test (`tests\Tests.Web`) or a unit test
   (`tests\Tests.Unit`).
   - When the change is about layout, navigation or other behavior that only a browser shows, ask the owner whether
     they want a Playwright test too. Recommend no unless the risk needs one: Playwright tests are long running.
   - Write no test suites, and run none. The owner does the manual test.

7. **Compile and test in the worktree.**
   - `dotnet build <worktree>\Speedmerchants.sln`
   - `dotnet test <worktree>\tests\<project> --filter <filter>`
   - Fix the code until both pass. A filter that matches no test is a fail.

8. **Land it.** Run, in one call:

   ```
   pwsh -NoProfile -File "{ClaudeHome}\skills\stream-kit\scripts\Commit-AdhocChange.ps1" -Repo <repo> -Session <session> -Id <Id> -Worktree <worktree> -Title "<one-line summary>" -TestProject tests\<project>\<project>.csproj -TestFilter "<filter>"
   ```

   The script exports the change, waits for the integrator's locks, applies the change to main, builds the solution,
   and runs the targeted test there. It commits only the change's own paths, then pushes the commit as the integrator
   does. Run it in the foreground. It can wait up to 30 minutes for the locks, so pass a long tool timeout.

   | Outcome | Meaning and next step |
   |---|---|
   | `COMMITTED <Id> <sha>` | Landed. Go to step 9. |
   | `REVERSED <Id> (build\|test failed ...)` | Main is unchanged. Read the log it names, fix the code in the worktree, re-run step 7, then run this step again. |
   | `REBASE <Id>` | Main moved under the change. In the worktree: `git stash push --include-untracked`, `git switch --detach <main HEAD sha>`, `git stash pop`. Resolve any conflict, re-run step 7, then run this step again. |
   | `DIRTY <Id> <paths>` | Another change to those paths is uncommitted on main. If the integrator is mid-apply, wait 5 minutes and retry. If the paths stay dirty, ask the owner. |
   | `ADHOC-BUSY <Id> ...` | The integrator held a lock for 30 minutes (a suite run). Tell the owner and offer to retry. |
   | `NOTHING <Id>` | The worktree has no change. Check that you edited the worktree, not main. |
   | `COMMIT SKIPPED` / `PUSH SKIPPED` | The machine's git policy does not allow it. Report it; do not work around it. |

9. **Close.**
   - File the shared-file stream-plan items.
   - Finish the request file.
   - Ask the owner whether to remove the worktree (recommend yes), and remove it only on a yes:
     `git -C <repo> worktree remove <worktree>`.
   - Report to the owner:
     - what changed, in plain English;
     - the commit;
     - the requirement ids;
     - the page or command to try by hand, and the rebuild that comes first (the owner rebuilds the stack).

## Questions

Ask every question, approval and decision with AskUserQuestion:
- put the recommended option first, marked "(Recommended)";
- ask at most 4 questions per round;
- read the artifact before you describe its current state in an option, and cite file:line.

Never take silence as approval. A requirement or mockup the owner has not approved blocks the request at that step.

## Rules

- **Writes only these:**
  - its own worktree;
  - `.streams\adhoc\`;
  - stream-plan inbox items, through `Send-InboxItem.ps1`;
  - `.streams\lessons\adhoc.md`, through `Add-Lesson.ps1 -Role adhoc`;
  - main, only through `Commit-AdhocChange.ps1`.
- **Never:**
  - touch `tasks.json`;
  - claim a task;
  - author a ticket;
  - integrate a built patch;
  - run a test suite;
  - run `git checkout`, `git reset` or `git clean` on the main tree;
  - commit any other way.
- **Requirement and mockup approval come before code**, every time, even for a one-line tweak. The record of each
  approval is in the request file.
- **Report in the owner's style:** caveman voice with the Clear Answer / Confidence Level / Key Caveats format, and
  times in local EDT.
