---
name: crewchief-run-monitor-2026-07-24
description: "durations now clock-style mm:ss.fff everywhere; per-step live clock in WorkloadRunMonitor; Steps-page single-step runs route through WorkloadRunCoordinator.StartStepAsync (Kind \"step\") and open the shared monitor"
metadata: 
  node_type: memory
  type: project
  originSessionId: f55edf44-80e4-4cc6-aeb0-d3c5a7423aa7
  modified: 2026-07-24T16:37:16.357Z
---

2026-07-24 run-surface changes (uncommitted):

1. **Duration format**: `RunDisplay.FormatDurationMs` is now clock-style `mm:ss.fff` (promotes `h:mm:ss.fff`) — NOT the old ms/s/m tiers ("742 ms"/"4 s"/"1m 23s") still described in [[crewchief-workload-and-runs]] (STALE there). Live clocks (`FormatElapsed`) stay `mm:ss` without ms (1s ticker → ms would be stale). Test pins clock-part parity with FormatElapsed.

2. **Per-step running clock**: `WorkloadRunMonitor.razor` duration cell shows a ticking `FormatElapsed(now - Coordinator.CurrentStepStartedUtc ?? run.StartedUtc)` on the executing row (rides the existing 1s ticker); final `.fff` value replaces it when the result lands.

3. **Single-step runs = coordinator runs**: `IWorkloadRunCoordinator.StartStepAsync(StepFile, promptedParams?)` wraps the step as a one-entry workload (INLINE snapshot via `JObject.FromObject(step.Step, StepSerializer)` — immune to concurrent library edits; prompted token values → GlobalParameters) and calls the private `StartAsync(..., kind: "step")` (`kind` param added; Kind was hardcoded "workload"). Steps.razor.cs no longer injects IUtilityOrchestrator/IRunHistory/INotifiers — run flow = `Coordinator.StartStepAsync` + `HandleStartResult` + shared `WorkloadRunMonitor` (old after-the-fact Run Results dialog DELETED). Consequences: step runs get live progress/cancel/notifiers via coordinator; single-run-at-a-time now applies to step runs too (previously concurrent steps allowed); step runs can now be Cancelled (previously only Succeeded/Failed). Monitor title is kind-aware ("Step Run"/"Workload Run"). `IsRunning(name)` derives from coordinator (Kind=="step" + name match); page subscribes `Coordinator.Changed` (IDisposable). [[crewchief-workload-and-runs]] skill's "Steps page writes its own RunRecord" description is STALE.

4. **Output truncation overhaul** (same day): there were TWO ceilings — `RunHistoryFile` persisted cap (`CrewChief:MaxStepOutputChars`, was 20000, head-only + "… (truncated)") AND `RunDisplay.TruncateForDisplay` 4000-char cap used ONLY by the Activity output dialog. A full Configuration.exe log (~25-30K) lost its tail = the failure evidence. Fixed: default raised to **100000** (both Program.cs fallbacks + both shipped appsettings.json + StepEditorCard display fallback — same config key everywhere), `RunHistoryFile.Truncate` now keeps **head+tail** (half budget each, "… (N chars omitted) …" middle marker), and `RunDisplay.TruncateForDisplay`/`MaxDisplayChars` DELETED (dialog renders persisted text raw — persistence owns the cap). CLI `history show` keeps its own separate console cap (untouched). Docs 32/40 updated.

Test gotchas: StepsPageTests' `MakeCommandLineStepFile` fixture deliberately carries a `{{Who}}` token — a Run click on it opens the token prompt, never the coordinator; StepEditorCard still injects IUtilityOrchestrator so page tests must keep that DI registration; a mocked-busy coordinator disables the row Run button (IsRunning) before a test can click it.
