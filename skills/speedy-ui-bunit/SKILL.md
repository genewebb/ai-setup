---
name: speedy-ui-bunit
description: >
  The `.b` leg of every vNext (speedmerchants) UI row — the bUnit component suite for a speedy-web
  Blazor screen or shared component. Use when writing or reviewing a `tests\Tests.Web` suite,
  deriving from `MonitorComponentTestBase`, satisfying the six-named-behaviour floor and its six
  canonical method-name tokens, mapping the floor onto a component row with no route, building a
  port fake (`*PortFakes.cs`) or a per-test harness, asserting a `data-*` figure or `role="status"`,
  deciding what a component test must NOT try to prove (posted forms, JS interop), or diagnosing a
  bUnit suite that fails intermittently under parallel MSTest. Not for the donor's own CrewChief
  bUnit suites — that is crewchief-testing.
---

Repo: speedmerchants (paths below are repo-relative)

# Speedy UI bUnit leg

`tests\Tests.Web` in `{SpeedyRepo}`. One suite per screen, and the suite is what
the row's `.b` leg delivers.

Hub: [[speedy-ui-screen-port]]. Siblings: [[speedy-ui-composed-graph]] · [[speedy-ui-playwright-axe]].

## The floor: six named behaviours, not six test methods

Criteria 9.2 / 10.2 / 11.2 require **six named behaviours per screen, all deriving from
`MonitorComponentTestBase`**. The floor grader (`u9-bunit-floor.ps1`, named in GOAL 9.2 and not yet
authored) greps for the six *behaviours by name*, never for six `[TestMethod]` attributes — a count
is a floor somebody games, and an Executor already padded two test titles once to satisfy a census
(09-05 14:50).

| # | Behaviour | What it asserts | **Canonical token** (must appear in the method name) |
| --- | --- | --- | --- |
| 1 | renders | the `data-speedy-<screen>` marker is on the page root, and on nothing else | `RendersItsMarker` |
| 2 | empty state | with no data the screen *says so* rather than rendering an empty table | `EmptyState` |
| 3 | primary action success | the control the screen exists for is present and carries what the endpoint needs | `PrimaryActionSucceeds` |
| 4 | primary action named refusal | the one high-risk wrong input is refused **by name**, not by a generic message | `RefusesByName` |
| 5 | store disagreement | when the store is unreachable, the screen shows **why** rather than a stale list | `StoreUnreachable` |
| 6 | `role="status"` | the notice region is announced, and `getByRole("status")` can read it | `AnnouncesStatus` |

**The tokens are the floor's machine form.** A floor stated in prose cannot be graded; these six
words can. The grader's construct, per suite: `void\s+\w*<Token>\w*\s*\(` in the comment-stripped,
string-blanked view, all six present. A suite is bound to its screen by naming the screen's marker
(`data-speedy-<screen>`) in an assertion; every page root under `src\Web\Components\Pages` that a
UoW-9/10/11 row added must have exactly one bound suite carrying all six. `MonitorPageTests` and
`WorkloadsPageTests` predate the floor and are exempt by name — `WorkloadsPageTests.cs` satisfies two
of the six by token today, so it is the template for STYLE, not for the floor.

More than six is fine and normal — `WorkloadsPageTests.cs` carries seventeen in the page class
(twenty-two in the file, with `MonitorStateTerminalTests`). Fewer is the row failing.

## Component rows: the six behaviours without a route

52.01 (value editor), 52.02 (Controls kit) and 53.03 (ops kit) render components, not pages. The floor
still applies; it maps like this, and the row report says which element carries each:

| # | For a component |
| --- | --- |
| 1 | the component's own marker (the plan names it: `data-speedy-value` for the editor) on its root, nowhere else |
| 2 | with an empty catalog / nothing picked, the component says so — no empty list, no blank pill |
| 3 | the component's one act produces exactly the string or event the consumer needs (the editor writes the byte-exact `{{…}}` string) |
| 4 | the one wrong input is refused by name (an unresolvable token, a pick from a catalog that has nothing) |
| 5 | with its store fake set `Unreachable`, the component shows why rather than an empty catalog |
| 6 | its validation / preview region is `role="status"` |

The row's grader may ask for more named behaviours on top (52.01's asks for `StaysVisible|WhileTyping`,
`VerbAndUnit|OneVerb`, `RendersAllSix|SourceTabs`); the six tokens are the floor beneath them.

## The base class

Every suite derives from `tests\Tests.Web\MonitorComponentTestBase.cs`:

```csharp
public abstract class MonitorComponentTestBase : BunitContext
{
    protected MonitorComponentTestBase()
    {
        JSInterop.Mode = JSRuntimeMode.Loose;
        Services.AddRadzenComponents();
    }
}
```

Two decisions are already made for you and must not be re-litigated per screen:

- **Loose JS interop, not strict.** These tests are about what the components render. Strict mode
  turns every Radzen component's first-render JS call into a failure that says nothing about the
  assertion being made.
- **Radzen's services are registered.** D2 keeps Radzen for UoW-9, so `RadzenDataGrid` is available
  and the base class is what makes it renderable.

`LiveSnapshot(...)` on the base class is the healthy-run snapshot for screens that need a whole
screen's worth of monitor state. Extend the base class rather than re-registering Radzen in a suite.
When a row adds a property to a snapshot or DTO that tests construct, the builders (`LiveSnapshot`,
`ScriptLiveRun`, `Sound()`) are in scope with the value they should set — 47.F found every component
rendering `(SCOPE UNKNOWN)` because the builder set none.

## Port fakes

Fakes live in `<Area>PortFakes.cs` (`MonitorPortFakes.cs`, `WorkloadPortFakes.cs`); the monitor's
harness-side fakes (`FakeCompositeRunProfileSource`, `FakeRampScheduleStore`) sit in
`MonitorHarness.cs`. Four conventions, all load-bearing:

1. **A fake answers whatever it was handed, defaulting to the honest empty.** Empty is what a store
   with nothing in it genuinely holds, and it is distinguishable from a failure because the fake
   reports success.
2. **Unreachability is a settable `string?`, not an exception.** `public string? Unreachable { get; set; }`
   and the read returns `RunStoreResult<T>.Unreachable(why)`. That is what makes behaviour 5
   assertable without throwing through the render tree.
3. **A write the screen must never perform THROWS.** `FakeRampScheduleStore.SaveAsync` throws
   `"The monitor never declares a ramp."` A read path that reached for a write should fail a test
   loudly rather than pass while doing something the architecture forbids.
4. **Never make a production dependency optional to satisfy a harness.** `MonitorHarness` documents
   the exact mistake: a positional constructor made the profile port `= null` by default, which let
   the graph compose a monitor with no profile source and nothing to say so. The port is required;
   the harness supplies one.

## One harness per test. Never a shared fixture.

`MonitorHarness` is constructed fresh in every test. The suite runs in parallel, and a shared
harness makes two tests that both move the clock fail each other intermittently — the failure mode
nobody ever manages to reproduce. Fixed anchors instead of `DateTime.Now`:

```csharp
public static readonly DateTimeOffset Noon = new(2026, 8, 30, 12, 0, 0, TimeSpan.Zero);
public static readonly Guid ScriptedRunId = Guid.Parse("11111111-2222-3333-4444-555555555555");
```

A fixed run id means a failure names the same id twice, which is the difference between a diagnosable
failure and a guess.

## Naming

`<Screen>_<Condition>_<Behaviour>()`, long and descriptive, with the canonical token inside it, so the
method name *is* the sentence the grader greps and the reader reads:

```csharp
LibrarySteps_RendersItsMarker_OnThePageRootAndNowhereElse()
LibrarySteps_WithNoStepsInTheLibrary_ShowsTheEmptyStateRatherThanAnEmptyTable()
LibrarySteps_ExportToLibrary_PrimaryActionSucceeds_AndCarriesTheSelectedNames()
LibrarySteps_ExportOverAnExistingName_RefusesByName()
LibrarySteps_WhenTheStoreUnreachable_ShowsWhyRatherThanAStaleList()
LibrarySteps_Notice_AnnouncesStatus_ThroughRoleStatus()
```

## What a component test must NOT try to prove

Two whole classes of thing, and both have a different home:

- **A posted form.** Every control on these static-SSR pages is bound by ASP.NET's own form-value
  binding, which lives in the request pipeline, not the component. A simulated submit exercises a
  handler with every field null. The posting half is proven in the service test
  (`WorkloadLauncherTests`) and in the browser (`tests\Tests.E2E`, `scripts\e2e\Invoke-*Proof.ps1`).
- **JS behaviour.** Interop is loose precisely so it is not asserted here. Sticky filters read in
  `OnAfterRenderAsync(firstRender)`, never `OnInitialized` — prerender has no `localStorage`, and
  that is a Playwright assertion, not a bUnit one.

What is left is what a component test is good for: that the markup carries the controls, the figures
and the markers the other two layers rely on.

## Asserting the machine contract

```csharp
Assert.IsTrue(page.Find("div.monitor").HasAttribute("data-speedy-workloads"));
Assert.AreEqual(0, page.FindAll("tr[data-workload]").Count);
```

The **absence** rule is assertable and must be asserted: an unmeasured figure emits *no attribute*,
so the test is `Assert.IsFalse(el.HasAttribute("data-..."))` plus an em dash in the text — never an
assertion that the attribute reads `"0"`.

## Running it

```powershell
dotnet test tests\Tests.Web\Tests.Web.csproj
```

Filter to one suite while iterating:

```powershell
dotnet test tests\Tests.Web\Tests.Web.csproj --filter FullyQualifiedName~<SuiteName>
```

Build the solution once before a run of graders on a memory-starved box; each filtered `dotnet test`
otherwise pays an incremental build.

## Sources

- `tests\Tests.Web\MonitorComponentTestBase.cs`
- `tests\Tests.Web\MonitorHarness.cs`
- `tests\Tests.Web\WorkloadsPageTests.cs` (the style template; 17 tests in the page class)
- `.loop\GOAL.md` criteria 9.2 / 10.2 / 11.2
- `{VaultDocsRoot}\speed-merchants\vNext\Design\UoW9_Plan.md` §0.5, §2 D8
