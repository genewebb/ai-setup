---
name: claude-account-switching
description: "Gene switches Claude accounts periodically to keep enough tokens for the vNext loop — what breaks across the switch (artifacts, watches, in-flight subagents) and what survives"
metadata: 
  node_type: memory
  type: reference
  originSessionId: 25a6f180-ace3-4c16-9718-60b837d6c54c
  modified: 2026-09-07T19:32:48.831Z
---

**Gene switches Claude accounts periodically so the loop has enough tokens to keep running** (stated 2026-09-07
15:31, during the 47.M resume). Treat a switch as EXPECTED, not as breakage, and never diagnose its symptoms as
data loss or as someone else's mistake.

**What does NOT cross accounts**

- **Artifacts.** `Artifact action: list` only ever returns the CURRENT account's pages. A URL owned by the other
  account is UNREACHABLE, not dead, and must not be recorded as dead or silently replaced. One page per account
  is the normal steady state; see [[vnext-schedule-format]] and the registry `.loop/tools/artifact-urls.json`.
  Identify the live account by listing and seeing which registered URL comes back.
- **Artifact live-update watches and comment auto-replies.** Armed per session on one account's page only.
- **The session itself, and therefore every in-flight background subagent.** A switch kills the session, which
  kills a dispatched Executor MID-EDIT. This is the likely cause of the 47.M death at ~15:05: the product work
  was committed, then the Executor was killed part-way through falsification 3 with the predicate still deleted
  from the working tree and an orphaned proof run still being served by two containers.
- **Quota display and model availability.** The loop's model rule (Fable orchestrates and verifies, opus
  Executes — [[loop-models-fable-plans-opus-executes]]) needs both available on whichever account is live.

**What DOES survive** — everything on disk or on the machine: `.loop/` state, PROGRESS, criteria, baselines, the
git repo and its commits, the docker stack, the warehouse database. A resume is therefore cheap and is always
preferable to a restart.

**Why it matters:** the symptoms mimic real failures. A missing artifact looks like a dead link, a half-applied
falsification looks like an Executor that went rogue, and orphaned containers look like a product defect.

**How to apply — on any unexplained session death, run this before planning anything:**
1. `git -C <repo> status --short` and `git log --oneline -3`. The operator may have COMMITTED the row before the
   switch, so HEAD may have moved past the dispatch point. Measure gate 3 and gate 4 against the TRUE dispatch
   HEAD, not the one the handoff names.
2. `docker ps -a`. An orphaned driver container plus a run still being served with no pwsh alive means a
   teardown never executed. Stop and remove the named driver, stop the coordinator, abort the live run, put the
   standing stack back up.
3. Assume the tree may hold a HALF-APPLIED falsification. Reverse-edit it by hand. **Never `git restore`** on an
   uncommitted row ([[do-it-right-not-a-patch]]).
4. Re-dispatch a fresh Executor told exactly what is already on disk; never re-dispatch the original prompt.
5. Give every dispatch a breadcrumb instruction: append one line to a scratch progress file at each internal
   milestone, so the next resume knows which stage was reached instead of inferring it from the tree.
