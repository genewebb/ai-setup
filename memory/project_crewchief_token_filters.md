---
name: project_crewchief_token_filters
description: "CrewChief {{token|filter}} pipe filters — date arithmetic and text manipulation, shipped 2026-08-24"
metadata: 
  node_type: memory
  type: project
  originSessionId: 230c53fa-c7bf-46a0-aabd-e4a5b09406ba
  modified: 2026-08-25T00:35:32.904Z
---

CrewChief tokens now support pipe filters: `{{ <source> | <filter>[:args] | ... }}`, e.g.
`{{$now|addDays:7|date:yyyy-MM-dd}}`, `{{StartDate|addDays:-1|date:yyyyMMdd}}`,
`{{$config:Paths:Root|substring:0,5|upper}}`. Shipped 2026-08-24, uncommitted. Suite 3158/0.

New sources `{{$now}}` / `{{$utcnow}}` / `{{$today}}`. 16 filters: addDays/addHours/addMinutes/
addMonths/addYears, date, startOfMonth, endOfMonth, substring, left, right, upper, lower, trim,
replace, padLeft.

Files: `TokenShapes.cs` (grammar, `SplitFilters`, `ValidateFilterChains`, `IsReservedInParameterName`),
new `TokenFilters.cs` (registry + evaluator), new `RunClock.cs`, `TokenFilterException` in
`ParameterResolver.cs`, plus `TextTemplater`, `ParameterResolver`, `UtilityOrchestrator`,
`WorkloadEngine.Validate`, `ValuePreviewService`, doc `21_WorkloadTokens.md`, tests
`TokenFilterTests.cs`.

Four non-obvious things worth remembering:

1. **`ReplaceTokens` evaluates every token TWICE** (`ValidateTokens` then `TokenPattern.Replace`). A live
   `DateTimeOffset.Now` would make the two passes disagree. `IRunClock`/`RunClock` freezes the instant in a
   **static AsyncLocal**, scoped by `UtilityOrchestrator` at run entry *only when not already frozen*, so a
   `RunWorkloadStep` child inherits the parent's instant. Chosen over a lazy-freeze singleton, which would
   freeze at first Web page render and stamp a stale time on a run days later.

2. **`SplitFilters` must NOT trim an unfiltered token.** Parameter keys match exactly (case aside), so
   `{{ Key With Spaces }}` resolves a parameter literally named with those spaces. Trimming broke
   `TextTemplaterTests.ReplaceTokens_TokenWithSpaces_ReplacesCorrectly`. Only trim when a pipe is present.

3. **Whole-value parsers had a latent bug**: `WholeConfigRefPattern`'s `(.+?)` eats `|`, so
   `{{$config:Api:Key|substring:0,5}}` parsed as a secret ref with item `Key|substring:0,5` and previewed
   as "not set". `TryParseWholeConfigRef` / `TryParseWholeRef` / `TryStripWholeConfigWrapper` now reject a
   body containing `|`.

4. **`TokenFilterException : UnresolvedParameterTokenException`** — same trick as
   `CircularParameterReferenceException`, so `UtilityOrchestrator`'s existing catch turns a filter failure
   into a step failure honoring `ContinueOnError` with zero new handling. The orchestrator now also
   **stops retrying** such deterministic failures.

Layer-1 static validation hangs on `WorkloadEngine.Validate` (blocks save at
`WorkloadEditor.razor.cs:1869`, re-runs before execute) plus `TextTemplater.CanResolveToken` (feeds badges
and `crewchief validate`). `|` is reserved in parameter names. Filtered secrets preview as "Secret —
filtered at run time", never a substringed mask. See [[crewchief-token-replacement]] skill,
[[reference_scenario_config_token_prefix]].
