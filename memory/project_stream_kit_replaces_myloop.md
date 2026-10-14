---
name: project-stream-kit-replaces-myloop
description: "2026-09-27 Gene retired /myloop for new work; green-field \"stream\" skill kit (one role per session, file claims, detached worktrees + patches, suites once per batch) is being built"
metadata:
  node_type: memory
  type: project
  originSessionId: 1c475457-1e54-4237-a0cd-5cdd61ea1bc1
  modified: 2026-09-28T14:27:33.771Z
---

On 2026-09-27 Gene said: "Lets not use /myloop you hae a green field to build something better". Earlier the same day: "We can use worktrees ... we can make whatever changes we need".

**Status:** MyLoop dispatch is paused (Set-Pause -On in speedmerchants). A background agent is building the stream kit: skills stream-plan, stream-author, stream-build, stream-integrate, stream-status and stream-approve. They live in Q:\Work\Work\03 Shared\work-ai\skills\ and are symlinked into C:\Users\agenewe\AI\skills. State lives in <repo>\.streams\, ignored via .git\info\exclude.

**How it works:**
- Each session runs one role in a self-paced loop and never prompts. Owner items go to .streams\owner\questions.md and .streams\owner\gates.md with the default already applied.
- Tasks are claimed atomically, and a stale claim can be taken over.
- Builders work in detached worktrees under C:\devops\worktrees\speedmerchants\<task>, with no branches and no commits. They hand off a patch, which the integrator applies to the dirty main tree.
- Builders run targeted tests only. The unit and integration suites run once per integration batch, and failures become fix tasks.

**Why:** a single MyLoop lead serialized everything. Per-row overhead and running suites per row made small fixes cost about an hour each, and workers sat idle for 290 minutes while tickets were being written.

**How to apply:**
- Don't start new work on /myloop.
- The pilot seed is RD-25, RD-33 and the RefData close-out, taken from the .loop\PLAN-*.md tickets. The group 2 drafts are in C:\tmp\speedy-build\group2\.
- Worktree removal still needs Gene's OK.
- The 15-minute cron update prompt is MyLoop-specific. Replace it with a stream-status prompt once the kit runs.

**Decisions so far (2026-09-27):**
- stream-plan v0.2 is generic. The start prompt MUST name the repo, the requirements path(s) and the explicit groups; nothing outside that scope is planned.
- `import` brings the reviewed G1 tickets (RD-25, RD-33, RD-19) in as the pilot.
- stream-integrate adds fix tasks itself.
- stream-author v0.1: a ticket plus a RED grader (no selftest), one skeptic subagent, claims the oldest ready task and runs under /loop, and logs defaults to .streams\owner\questions.md.
- stream-build v0.1: a detached worktree whose base is HEAD + the dirty diff + untracked files + the patches of built dependencies. Hands off a patch and runs a blind verifier with one fix pass.
- stream-integrate v0.1: a single integrator lock. It applies each patch as soon as it is built, runs the suites once per group, and has a 3-run cap. A conflict bounces the task back to ticketed. Gates pass by command.
- stream-status v0.1: a live page plus 5 terminal lines, run by /loop 15m. Gene chose that it BREAKS stale claims (author 30 min, build 45 min, integrator 20 min).
- Built 2026-09-27: 6 skills (stream-kit plus the 5 roles) are symlinked. The scripts are in stream-kit\scripts. Test-StreamKit.ps1 passes 41/41 against a throwaway repo.
- PILOT IMPORTED 2026-09-27 into speedmerchants\.streams:
  - G1.T01 (was RD-25) and G1.T02 (was RD-33) are ticketed.
  - G1.T09 (was RD-19) is the integration task and depends on T01 and T02.
  - Gate G1.G10 depends on T01.
  - Grader shims are in .streams\graders.
  - Next: Gene opens the sessions and deletes the MyLoop cron when status starts.
- Pilot gotcha: the .loop criteria graders take `-Repo`, not the kit's `-Root`. Import needs a shim grader per task. RD-25's grader also hits the live web host (127.0.0.1:5310), which is not worktree-isolated.

**2026-09-28 inboxes + recovery (kit maintained on demand via `/stream-kit inbox`; the kit has NO loop, so its inbox only moves when a session runs that):**
- Every role has `<repo>\.streams\inbox\<skill>.md` (6: plan, author, build, integrate, status, kit). Write only through `Send-InboxItem.ps1` / `Set-InboxItem.ps1`: `taken` is lock-checked (exit 8 ALREADY). Hand appends let two authors work one item on 9/27.
- Integrate-Patch prints `SUSPECT` when main is red only on clauses that passed in the worktree on identical content. The task goes to `planned` with its patch kept. Builders run `Restore-TaskPatch.ps1` (step 3b) and don't rebuild.
- Invoke-Grader sets `STREAM_SINCE_UTC`. `Test-GraderPortability.ps1` flags mtime / `.loop\rows` / unset `-Since` graders; plan import runs it.
- Add-Tasks -Role integrate: a fix on an integrated task's files is CHAINED after it (it used to be a dead note), and it reopens a done integration task.
- Integrate commits each integrated task's paths (added by another session 9/27 19:12).
- 9/28 03:40Z: Update-Task -AddWriteSet used to refuse any file of a non-done task, even integrated or dependsOn-chain ones (G2.T19 stalled). Fixed: those are ordered and allowed; self-test cases 8c.
- Builders skip the 10-minute beat during long edits, so status breaks live claims (G2.T31). Salvage by running Export-TaskPatch on the old worktree and setting artifacts.patch, so the next builder's Restore-TaskPatch reuses the work.
- Plan edits that bypass Add-Tasks need a board-wide check: no cycles and no open write-set overlap without a dependsOn chain.
- 9/28 10:25 EDT: /stream-coordinator v0.1 was created (the supervisor loop codified; run under /loop 20m).
  - New kit scripts: Revise-Task.ps1 (batch plan edits; refuses a batch that leaves the board unordered), Test-BoardOrder.ps1 and lib\Board.ps1.
  - stream-plan must use both. The first live board check found 33 unordered overlaps, sent to plan as IN-...-41a1.
- 9/28 overnight lessons:
  - Stream sessions stalled for hours on bash approval prompts (Gene set auto-approve ~12:45Z). Unattended runs need their commands pre-approved.
  - The c7 supervisor cron registered but did not fire 04:32Z-12:39Z (cause unknown). Don't rely on one session's cron alone.
  - Planning is the bottleneck: authors file ~5 write-set revisions an hour, so a live stream-plan inbox session is required.
- Kit fixes on 9/28:
  - Export-TaskPatch: `git add -N .` staged deletions, so they dropped from every patch. Now only untracked files get intent-to-add, and stdout is read without stderr warnings.
  - Integrate-Patch: CS2012 / file-lock failures are RETRY, never SUSPECT.
  - Invoke-Grader: `.streams\main-grader.lock` serializes grader runs on the main tree.
  - Get-StreamStatus: liveness counts claim beats and the integrator lock (`integ-` sessions map to integrate).

Related: [[feedback-run-suites-once-at-group-close]], [[feedback-one-row-per-write-set]], [[feedback-worktrees-allowed-must-integrate]].

**2026-09-27 19:07 — integrator now COMMITS.** Gene: "all commits should be automated at this stage". Integrate-Patch.ps1 commits exactly the patch's paths right after grader PASS on main (msg `<task>: <title>`, `-NoCommit` opts out); a failed commit is logged to decisions.md and left uncommitted. Self-test extended (commit holds only patch paths), 0 fails. Skill docs updated (stream-integrate A3 + rules, stream-kit SKILL, howto). Builders/authors still never commit.
