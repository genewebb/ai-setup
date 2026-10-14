---
name: speedmerchants-cursor-testoutput-path
description: SM test-result output retargeted from .cursor/documentation to root documentation/ (gitignored) on 2026-07-30; .cursor is fully gone
metadata: 
  node_type: memory
  type: reference
  originSessionId: 164e7710-52ca-4205-8c9e-769af15611f2
  modified: 2026-07-30T14:36:20.713Z
---

speed-merchants test-result markdown output historically went to `.cursor/documentation/` (a path baked into test code, NOT Cursor IDE state). **2026-07-30: retargeted to `{solutionRoot}\documentation\`** in `TestResultsHelper.cs` (Testing.SpeedMerchants.TestHelpers) and the 5 `Path.Combine` sites in `RecordMixManagerIntegrationTests.cs`; `/documentation/` added to the repo `.gitignore`. Clean build verified. So: an untracked root `documentation/` folder full of timestamped run dumps is expected and disposable; `.cursor` should never reappear. Same-day cleanup also deleted `.superpowers` (old SDD artifacts), `.vs` (user off Visual Studio), and `.claude` (inert — see [[workspace-start-convention]]). Stale mentions of `.cursor/` remain in `TestAuto.Web\Documentation\00_SolutionInventory.md` + `CompleteReference.md` (descriptive docs only).
