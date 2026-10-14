---
name: machine-sync
description: Carry AI setup edits between two machines (for example SMVMTR1 and CORPLTR94, either direction) - the AI corpus (skills, agents, commands, hooks, lib, setup), the shared pwsh profile and the stream-host scripts. Three-way compare against the last agreed copy, so it copies only what changed on the source, leaves target-side edits alone and reports conflicts. Use for /machine-sync, "sync TR1 back to the laptop", "push my laptop tweaks to TR1", or before re-staging a machine.
---

# machine-sync

Runs on the machine that holds the build area, `{DeployRoot}` (blank on machines that are only targets: say so and stop).
Machines and where each item lives on them are in `{DeployRoot}\machines.json`, as seen from this machine.

```
pwsh -NoProfile -File {DeployRoot}\steps\Sync-Machine.ps1 -Source <machine> -Target <machine> [-What corpus,profile,streamhost] [-Apply] [-Delete] [-Force] [-Publish]
```

## How it decides

The base is the content both machines last agreed on (`{DeployRoot}\sync-base\`, written by every apply and by
`Stage-Machine.ps1`). Per file:

| Changed since the base on | Result |
|---|---|
| source only, or new on the source | copied to the target |
| target only | left alone: "newer on target", sync the other way |
| both | CONFLICT, left alone; `-Force` takes the source |
| deleted on the source | reported; removed only with `-Delete` |

Every overwritten or deleted file is copied first to `{DeployRoot}\sync-backup\<stamp>\`.

## Steps

1. Ask which direction if the request does not say (AskUserQuestion; recommend the machine the user says they edited
   as the source).
2. Dry run (no `-Apply`) and show the user the lists: copies, conflicts, newer on target, deletions.
3. Conflicts: show the diff of each (`Compare-Object` of both copies) and ask which side wins. Never pass `-Force` or
   `-Delete` without the user's answer.
4. Apply with `-Apply`. When the target holds the corpus source (the build machine), add `-Publish` so the corpus goes
   to the shared AIWork copy as well, unless the user wants to review first.
5. Tell the user what lands where:
   - corpus on the target: the next `ai` start there installs it (or `/machine-config apply`);
   - profile: open a new pwsh;
   - stream-host: nothing to run.
6. "Newer on target" files are edits made on the target. Offer the reverse sync.

## Notes

- First sync of a pair with no base: every file both sides have that differs counts as a conflict. Record a base
  first with `-SetBaseFrom <machine>` once the user confirms that machine holds the agreed content.
- `Stage-Machine.ps1` refuses to mirror over a target edited since its last stage or sync; run this skill target -> build
  machine first.
- A new machine needs an entry in `machines.json` (corpus, profile, streamhost paths as reached from the build machine).
