---
name: unit-tests-no-outside-artifacts
description: User rule — unit tests must never read fixtures/artifacts from outside the test project folder
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 0d3e6080-6cbb-498b-84b2-6ad6084ac90d
  modified: 2026-08-19T21:18:36.326Z
---

Unit tests must not rely on artifacts outside the project folder (user ruling 2026-08-19, verbatim: "Unit tests should not rely on artifacts OUTSIDE of the project folder so this issue does not happen again").

**Why:** CrewChief's ConnEx tokenization unit tests read real Connect portal exports from machine-local `C:\tmp\ConnectExports`; a scratch-folder wipe silently broke 64 tests (`Assert.Fail` on missing fixture). Recovered files from `C:\tmp\Archive\ConnectExports` and moved them into `CrewChief.Tests.Unit\TestData\ConnectExports\` (csproj already copies `TestData\**\*`).

**How to apply:** Fixture paths resolve via `Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "TestData", ...)`. When writing/reviewing any test that reads a file, verify the file is committed inside the test project and copied to output. Related: [[atomic-tests]], keep the Assert.Fail-not-Inconclusive doctrine for missing fixtures.
