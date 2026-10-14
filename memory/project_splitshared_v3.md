---
name: project_splitshared_v3
description: "SplitShared v3 plan state — TestAuto.Shared clean-architecture split; v1 reverted, Caching/Security shipped, logging-primitive cross-cut is the key blocker"
metadata: 
  node_type: memory
  type: project
  originSessionId: a8ab9559-4910-4c2f-9ee0-2e0e7a5cf54b
---

Planning-only (no coding authorized) effort to split `TestAuto.Shared` into a clean-architecture layering. Docs in `…\99 Documentation\speed-merchants\planning\`: `SplitShared-v3.md` (the plan, supersedes v2 conceptually — v2 stays on disk as history), `SplitShared-v3-ImplementationPlan.md` (B0→B12 steps, build checkpoints, owner-run reverts), `clean_architecture_review.md` (the architecture review v3 anchors to), `CALearning.md` (conceptual gates note — still v2-era/stale).

Verified ground truth (2026-06-20), which contradicts the on-disk v2 plan:
- **v1 was fully reverted.** `TestAuto.Shared.Abstractions` does NOT exist; all ~44 interfaces are still in `TestAuto.Shared/Interfaces/`. Every "moved in v1" note in v2 is false — v3 moves everything fresh.
- **A different split shipped** (commit `b5012216`): `TestAuto.Shared.Caching` + `TestAuto.Shared.Security` (Infrastructure tier), but their interfaces still live in `TestAuto.Shared/Interfaces/`, so both still reference the whole monolith. Directionally correct, incomplete.
- **THE key blocker (not in v2): logging-primitive cross-cut.** `LoggerTagExtensions` (`*WithTag` Serilog ext) + `LogTagConstants` + `EntityNames` are used by almost every concrete class incl. Caching/Security. Moving contracts to Abstractions is NOT enough to free the Infrastructure tier — these leaf primitives must also move down into Abstractions (v3 §3.3, Gate E2). Risk register #2.

Locked decisions: ONE combined `TestAuto.Shared.Abstractions` (not Domain+Abstractions); Abstractions NuGet = Profisee.Cdp + Newtonsoft + FluentValidation + **Serilog** (Serilog added for the primitives); scope = Shared split only (Caching/Security/Http reconciled; review items C4/C7/C10/C11 out of scope). 5 CopyToHosts plugins need type forwarding: Connect, Utilities, Records, Metadata, Matching. EntityArtifactHelper + RestClientAdapter are dead code (delete). PowerShellValidationService uses Process/pwsh.exe (no PowerShell.SDK). Test settings file is `coverlet.runsettings` (not Tests.runsettings).

Relates to [[project_repos]], [[project_tech_stack]], [[feedback_no_commits]].