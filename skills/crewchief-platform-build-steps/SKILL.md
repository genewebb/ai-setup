---
name: crewchief-platform-build-steps
description: >
  CrewChief's four-stage platform-build step family — AdoBuildDownload, BuildUnzip, BuildVerify and
  BuildPublish — whose entire contract is a marker file because CrewChief has no step-output-to-step-input
  piping. Use when authoring or debugging a platform-build workload, working on BuildDownloadMarker /
  AdoBuildClient / the four executors / AdoBuildProber, diagnosing a build that extracted or published the
  wrong version, a download that times out at 100 seconds, an expired Azure DevOps PAT, or a publish that
  destroyed the last good CurrentBuild.
---

Repo: speed-merchants (paths below are repo-relative)

# CrewChief platform-build steps

A four-stage family added 2026-08-27: **AdoBuildDownload → BuildUnzip → BuildVerify → BuildPublish**.
It exists to pull a Profisee platform build off Azure DevOps and publish it to a share, typically on a
scheduled night run.

## When to Use

- "Download the latest platform build and publish it"
- "The workload published an old build" / "published an unverified build"
- "The download aborts after ~100 seconds"
- "The preflight says AdoBuild failed"
- Adding a stage, or changing what a stage reads

## The contract is a MARKER FILE, because steps cannot pipe

**CrewChief has no step-output-to-step-input piping.** So stage 1 writes `latest-download.json` into the
download directory, and **every later stage takes ONLY `downloadDirectory`** and reads the build identity
back out of that marker.

That is not a workaround — it is what makes the family safe. A build finishing mid-workload **cannot**
switch what gets extracted or published, because the identity was frozen at download time.

```
AdoBuildDownload  → writes latest-download.json { buildNumber, folderName, downloadedUtc, ... }
BuildUnzip        → reads it, extracts, stamps unzippedUtc
BuildVerify       → reads it, verifies, stamps verified: true
BuildPublish      → reads it, refuses unless verified: true, then robocopy /MIR
```

### Marker rules, each bought with a failure

| Rule | Why |
|---|---|
| Each stage **stamps its own timestamp** and **refuses a marker missing its prerequisite** | A stage cannot run out of order |
| A fresh download must **RESET** `unzippedUtc` and `verified` | Otherwise a new zip **inherits the old build's verified flag** and publishes unchecked |
| A corrupt marker reads as **"nothing known"** — redo the work | Never as "we have it". Reading a damaged marker optimistically is how you publish a build nobody has |
| `.zip.partial` is **never consumed** | A part-downloaded artifact is not an artifact |

### The other stage mechanics

- **Extract** to `<folder>.extracting`, then rename. No half-extracted folder is ever named as if complete.
- **Publish** is `robocopy /MIR`, gated **solely** on `verified: true`. `/MIR` mirrors, so an unverified
  publish **destroys the last good `CurrentBuild`** — which is why the gate is the only condition.
- **Retention prune** requires **both** the versioned folder shape **and** a `build-info.json`. A folder
  that looks like a build but carries no info file is left alone rather than deleted.
- A **remote** target routes through the box-prep WSMan transport with **mandatory Run As** — refused, never
  falling back to process identity. See [[crewchief-remote-box-prep]].

## `buildNumber` is derived, with no fallback

It must match `major.minor.patch.revision` and is **derived** to a folder name:

```
26.3.0.767  →  26R3B767
```

`BuildDownloadMarker.TryDeriveFolderName` has **no fallback** — a build number that does not match the
shape is a refusal, not a best-effort name.

## `AdoBuildClient` — three non-obvious choices

| Choice | Reason |
|---|---|
| Pins **api-version 7.1** | Not "latest" |
| **Basic auth over `base64(":<PAT>")`** | The Azure DevOps PAT convention — empty username, PAT as password |
| **Infinite `HttpClient` timeout** | Deliberate. The 100-second default **aborts every real ~423 MB download.** The step's own `timeoutSeconds` is the only clock |
| Artifacts selected by **resource TYPE** | The artifact *name* embeds the version, so matching on name would need the version you are trying to discover |

That third row is the one people "fix" and break.

## Preflight — `AdoBuild` is the ninth capability

`AdoBuildProber` backs `StepCapability.AdoBuild` (see [[crewchief-capability-preflight]]). It is a
capability rather than a step-time failure **because the download is a ~423 MB artifact on a scheduled
night run**: an expired PAT with no preflight surfaces as a transport error hours later, part way through a
workload, with the marker describing a build nobody has. A probe costing one cheap authenticated GET names
the cause before any step executes, and the CLI reports it as exit 4.

Two things about the verdict:

- It is **the only capability that does not exercise a Windows identity at all** — Azure DevOps
  authenticates the PAT, so the verdict is about the **token**, not `EffectiveIdentity`.
- The three failure causes are kept apart in the verdict text **on purpose**: PAT invalid/expired, PAT
  lacking the Build (Read) scope, and network unreachable have three unrelated fixes. Collapsing them is
  how an operator reissues a token that was never the problem.
- `AdoBuildProbeTarget` splits `Query` (carries the PAT) from `Display` (the organization URL and project,
  **never** the token), because every verdict is rendered in badges, tooltips, the preflight panel and the
  run log. Modelled on `SqlProbeTarget` for the same reason.

## Sources

- `CrewChief\CrewChief.Engine\Services\BuildDownloadMarker.cs`
- `CrewChief\CrewChief.Engine\Services\AdoBuildClient.cs`
- `CrewChief\CrewChief.Engine\Executors\AdoBuildDownloadExecutor.cs`
- `CrewChief\CrewChief.Engine\Executors\BuildUnzipExecutor.cs`
- `CrewChief\CrewChief.Engine\Executors\BuildVerifyExecutor.cs`
- `CrewChief\CrewChief.Engine\Executors\BuildPublishExecutor.cs`
- `CrewChief\CrewChief.Engine\Steps\AdoBuildDownloadStep.cs` (and the three sibling step types)
- `CrewChief\CrewChief.Engine\Capabilities\Probers\AdoBuildProber.cs`
- `CrewChief\CrewChief.Engine\Capabilities\StepCapabilityRequirements.cs`
- `CrewChief\CrewChief.Web\Documentation\53_StepGuideAdoBuildDownload.md` through `56_*`
- `CrewChief\SampleContent\workloads\download-latest-platform-build.workload.json`
