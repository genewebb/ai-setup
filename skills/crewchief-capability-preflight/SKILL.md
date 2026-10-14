---
name: crewchief-capability-preflight
description: >
  CrewChief's pre-run Capability Advisor — nine step capabilities, their probers, the four-state verdict
  model, the retry-then-hard-block preflight that refuses a run before any step executes, and the UI badges
  and CLI exit code 4 that surface it. Use when a run is blocked before it starts, when adding a capability
  or prober, when working on PreflightGate / CapabilityAdvisor / CapabilityCheckService, when a capability
  badge shows Unknown or NotProbed, when reasoning about effective identity or the logon-attempt budget, or
  when looking for a bypass flag (there isn't one).
---

Repo: speed-merchants (paths below are repo-relative)

# CrewChief Capability Preflight

Before CrewChief runs a workload or step, it asks a different question from "is this config valid?" — it
asks **"can the identity this run will actually use do the things these steps need?"** That check is the
Capability Advisor. Its verdicts drive badges in the UI, and a `Failed` verdict **hard-blocks the run**
before a single step executes.

This is deliberately separate from validation ([[crewchief-orchestration]]'s `ValidateScenario`), which
only inspects the step definition. A perfectly valid step still fails at 3 a.m. because the service account
lost local-admin rights on a rebuilt box; that is what this subsystem catches.

## When to Use

- "Why won't this workload start? It says a capability failed."
- "Where do I add a new capability / prober?"
- "What does an `Unknown` capability badge mean — is it blocking?"
- "How do I bypass the preflight for this one run?" (You don't — see below.)
- "Why did the advisor bless the wrong account?"
- Working on `CapabilityAdvisor`, `PreflightGate`, `CapabilityCheckService`, or any `*Prober`.

## The nine capabilities

`StepCapability` (`CrewChief.Engine/Capabilities/CapabilityModel.cs`). **Each value corresponds to exactly
one `ICapabilityProber`** — that one-to-one rule is stated in the enum's own doc and is what keeps the
subsystem tractable.

| Capability | Asks |
|---|---|
| `LocalAdmin` | Does the effective identity hold local Administrator rights on the machine the step runs on? |
| `RemoteRunAs` | Does a Run-As credential pair (user id + password) resolve for a remote target? |
| `LocalLogon` | Can the Run-As account create a **local logon session on this machine**? |
| `RemoteWinRm` | Is a WinRM / PowerShell Remoting endpoint reachable and authenticable on the target? |
| `SqlAuth` | Does a SQL connection (Windows or SQL login) authenticate against the target server/database? |
| `ShareFirstHop` | Can the effective identity open the UNC share directly? |
| `ShareSecondHop` | Is the share reachable **from the remote target** (the `ShareMount`/`CC_SHARE_PATH` pattern)? |
| `ConnExParameters` | Does every `{{token}}` a ConnEx step consumes (inline artifact, resourceId, effective BaseUrl/ApiKey incl. `RestClients:Connect:*` fallbacks) resolve to a **non-empty** value? Local, deterministic, computed live — added 2026-08-19 (user decision) after connect-import workloads shipped with empty `DbUsername`/`DbPassword` globals. Missing AND empty are both Failed/Deterministic (hard-block). Presence only — a present-but-wrong API key still 401s at run time. In `ResolvesFromStepScope` (triple is `(ConnExParameters, null, null)` for every ConnEx step). |
| `AdoBuild` | Is Azure DevOps reachable **and** is the step's Personal Access Token still accepted? For the platform-build family (`AdoBuildDownloadStep`, `BuildUnzipStep`, `BuildVerifyStep`, `BuildPublishStep` — see [[crewchief-platform-build-steps]]). **The only capability here that does not exercise a Windows identity at all** — Azure DevOps authenticates the PAT, so the verdict is about the TOKEN, not `EffectiveIdentity`. Three failure causes are kept apart in the verdict text on purpose (PAT invalid/expired, PAT lacking Build-Read scope, network unreachable) because they have three unrelated fixes and collapsing them is how an operator reissues a token that was never the problem. It is a capability rather than a step-time failure because the download is a ~423 MB artifact pulled by a SCHEDULED night run: an expired PAT with no preflight surfaces hours later, part way through a workload, with the marker describing a build nobody has. `AdoBuildProbeTarget` splits `Query` (carries the PAT) from `Display` (the org URL and project, never the token) for the same reason `SqlProbeTarget` does. |

> [!important] `LocalLogon` is deliberately NOT folded into `LocalAdmin`
> They fail for unrelated reasons with unrelated fixes. `LocalLogon` fails with **1385** (the account lacks
> *Log on as a batch job* / *Allow log on locally*), **1326** (wrong credential), or **1058** (the Secondary
> Logon service is disabled). Merging them would report *"not an administrator"* for an account that **is**
> one but cannot log on — which sends the operator off editing group membership that was never the problem.

Script-bodied steps (CommandLine, PowerShell, HTTP, curl, CLU) deliberately get **no** capability check:
CrewChief cannot know what an arbitrary script will touch, and guessing would produce false blocks.
**ConnExStep graduated out of this rule 2026-08-19** — its parameter surface IS derivable, so it derives
`ConnExParameters`. Backlog for further checker enhancements (gateway acceptance probe, other step
families, semantic artifact checks): `speed-merchants\planning\Backlog_CapabilityChecker_Enhancements.md`.

## The four-state verdict — only ONE of them blocks

`CapabilityStatus`:

| Status | Meaning | Blocks a run? |
|---|---|---|
| `Satisfied` | The probe succeeded | No |
| `Failed` | The probe ran and failed | **YES** |
| `Unknown` | The probe itself errored, unclassifiable | **No** (spec D2) |
| `NotProbed` | Lazy network capability, no cached verdict yet | **No** (spec D2) |

`Unknown` and `NotProbed` never block. That asymmetry is the design's central safety property: **absence of
evidence is not evidence of absence**, and a probe that cannot run must never be the reason an operator
cannot run their workload. Only a verdict that positively demonstrates the capability is missing earns a
block.

`FailureClass` splits `Failed` into transient vs deterministic. `PreflightPolicy.ProbeWithRetryAsync`
(`:120`) retries only the transient ones — `CrewChief:Preflight` config (`PreflightOptions`, `:29-41`)
supplies `TransientRetryCount` (default **2**), `TransientRetryDelaySeconds` (default **2**), and
`RemoteProbeCacheMinutes` (default **5**). A probe that throws yields `Unknown`, not `Failed`, so a broken
prober cannot block anyone.

## The hard block — and the bypass that does not exist

`PreflightGate` (`CrewChief.Web/Services/PreflightGate.cs`) is **the one implementation** of the
run-initiation block, shared by all four run-initiating pages; `RunCommand` gates `run`, `resume` and
`step` on the CLI side.

- `BlocksAsync(...)` (`:77`) is the only writer of `Block` (`:50`); `Blocked` is **derived** from the verdict
  list by `PreflightResult.From`, never set independently — so "any `Failed` verdict" and "blocked" cannot
  drift apart.
- On a block: the run **never starts**, no step executes, and **no `runs.json` record is written**. The CLI
  returns the dedicated exit code **`PreflightFailed = 4`** (see [[crewchief-cli]]) after printing every
  failing verdict's remediation.

> [!danger] There is no bypass flag — anywhere
> Not on the CLI, not in the Web UI, not in configuration. This was an explicit ruling, and `PreflightGate`
> exists as a shared class rather than six copies of six lines precisely so no call site can quietly grow
> one. If you are about to add a `--force`, that is the thing this design says no to.

### Check the identity the run will ACTUALLY use

The step bodies handed to the gate must be the ones that will execute, which is why the selectors are part
of the gate's public surface rather than each caller's business:

| Selector | Use |
|---|---|
| `StepBodies(WorkloadFile?)` / `(StepFile?)` / `(UtilityStepBase?)` | A fresh run |
| `StepBodiesForRestart(workload, startIndex)` (`:206`) | Skips everything before the restart point |
| `StepBodiesForResume(workload, priorRun)` (`:219`) | Skips steps that already succeeded |

A step that will be **skipped** must not be able to block the run — checking it would report a failure for
work that is never going to happen.

Compose-time callers must resolve the step through `WorkloadStepMaterializer.Materialize`, which applies
**both** the workload-level Run-As inheritance **and** the global-parameter merge onto a copy. Applying only
the first produced false *"no Run As credential resolved"* verdicts that hard-blocked legitimate runs — see
[[crewchief-workload-and-runs]].

`EffectiveIdentity.For` must agree with `BoxPrepRouting.Decide` about which account a step runs as. They
drifted once, and every per-component test stayed green while the advisor blessed the wrong account; the
`LocalRunAsOneTruthTests` agreement test exists for that reason ([[crewchief-testing]]).

## Badges must never probe on the render path

The UI surface — `CapabilityBadge`, `CapabilityCheckPanel`, `CapabilityVerdictList`, `PreflightPanel`, plus
`CapabilityCheckService` / `CapabilityCheckState` behind the bulk **Check Capability** action — renders from
**cached** verdicts only (`allowNetworkProbes: false`). A network probe is triggered exclusively by the
explicit **Probe** button.

The reason is not performance: probes authenticate, and authentication failures **move real accounts'
lockout counters**. A badge that probed on render would burn logon attempts every time a list repainted.
`CapabilityProbeCache` shares verdicts so a bulk check does not re-probe per row, and `LogonAttemptGuard`
enforces a budget. Probers are therefore tested with **counting** fakes — the load-bearing guarantees are
negative ("probed exactly once", "never on the render path", "never started a run").

## Registration lives in the ENGINE, not the Web layer

`AddCrewChiefCapabilitySubsystem` is in `CrewChief.Engine/Capabilities/CapabilitySubsystemRegistration.cs`,
**unlike** the two secrets extensions which live under `CrewChief.Web/Services/`. `CrewChief.Cli` must share
the subsystem and cannot reference `CrewChief.Web`. `CapabilityCompositionRootTests` pins every prober seam
twice — structurally *and* behaviourally — because a `_ => null` stub is otherwise indistinguishable from a
legitimate null. See [[crewchief-architecture]].

## Sources

- `CrewChief\CrewChief.Engine\Capabilities\CapabilityModel.cs`
- `CrewChief\CrewChief.Engine\Capabilities\CapabilityAdvisor.cs`
- `CrewChief\CrewChief.Engine\Capabilities\PreflightPolicy.cs`
- `CrewChief\CrewChief.Engine\Capabilities\CapabilityProbeCache.cs`
- `CrewChief\CrewChief.Engine\Capabilities\EffectiveIdentity.cs`
- `CrewChief\CrewChief.Engine\Capabilities\StepCapabilityRequirements.cs`
- `CrewChief\CrewChief.Engine\Capabilities\CapabilitySubsystemRegistration.cs`
- `CrewChief\CrewChief.Engine\Capabilities\Probers\` (7 probers + `LogonAttemptGuard`, `ProcessIdentity`)
- `CrewChief\CrewChief.Web\Services\PreflightGate.cs`
- `CrewChief\CrewChief.Web\Services\CapabilityCheckService.cs`
- `CrewChief\CrewChief.Cli\Commands\RunCommand.cs`, `CliExitCodes.cs`
- `CrewChief\CrewChief.Web\Documentation\45_OpsCapabilityPreflight.md`

## Related

[[crewchief-cli]] · [[crewchief-remote-box-prep]] · [[crewchief-architecture]] · [[crewchief-testing]] · [[crewchief-workload-and-runs]] · [[crewchief-orchestration]]
