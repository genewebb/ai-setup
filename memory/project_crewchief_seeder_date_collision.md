---
name: crewchief-seeder-date-collision
description: "FIXED 2026-07-31 — SampleContentSeeder's date-keyed versioned write silently dropped a same-day second revision; now takes the next free -N and logs when it cannot"
metadata: 
  node_type: memory
  type: project
  modified: 2026-07-31T12:40:43.900Z
  originSessionId: 26ec27c2-0337-4ce1-86d5-d034196dec19
---

FIXED 2026-07-31 (found by a verify agent during the capability-badge work, fixed in the same session).

**The bug.** `CrewChief.Web\Services\SampleContentSeeder.cs`, the `SeedAction.WriteVersioned` branch. The versioned file name is `<base>-<shippedUtc><suffix>` — **keyed on the calendar date and nothing else** — and the write was guarded by a bare `if (!File.Exists(versionedPath))`. So a sample whose source changed **twice on the same day** hit the already-taken name on the second install and returned having written nothing, logged nothing, and **not incremented `written`** — `Seed` reported a success count that had quietly excluded it. Classic silent failure: the missing log line was what made it invisible.

**The fix.** Three outcomes are now distinguished explicitly instead of collapsed into one skip:
- name free → write it (normal case)
- name taken, **identical** content → genuine idempotent no-op, deliberately no warning (a repeat install of the same thing is not a problem)
- name taken, **different** content → take the next free `-N` (`<base>-<date>-2`, `-3`, …, bounded at 25); only running OUT of names is a real failure, and that logs `_logger.Warning` naming the resource, the stem and the folder — never swallowed

**The subtlety worth remembering.** The "already installed?" comparison must hash `WithName(content, candidateBase)`, NOT the raw embedded resource. `WithName` rewrites the sample's internal `"name"` to match its versioned file name, so it differs per candidate — comparing raw content would never match and would pile on a fresh `-N` copy on **every single install**. That is what `Seed_VersionedCopyAlreadyInstalled_IsIdempotent_AndDoesNotSpawnNCopies` pins.

`GetStatuses()` needed no change: it maps the `SeedGate.Decide` result to a display state and never computes a versioned name, so it cannot drift from this logic.

Tests in `CrewChief.Tests.Unit\Web\SampleContentSeederTests.cs`. To reach the WriteVersioned branch from a test: seed, edit the sample in place so its content differs from the embedded resource, then delete `.seed-manifest.json` so it reads as "untracked but present" (the `ArmWriteVersioned` helper). Diff file-name sets before/after rather than globbing `base + "-*"` — several shipped samples share a `26r2-`/`26r3-` prefix and a glob sweeps in unrelated files. Red was verified by temporarily setting the attempt bound to 1: `Expected:<1>. Actual:<0>`.

Related: [[project_crewchief_smart_seed]], [[project_crewchief_templates_selective_install]], [[project_crewchief_capability_badge_invalidation]].
