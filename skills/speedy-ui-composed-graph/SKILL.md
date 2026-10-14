---
name: speedy-ui-composed-graph
description: >
  The `.c` leg of every vNext (speedmerchants) UI row — the composed-graph resolution test proving a
  speedy-web screen's ports come out of a real `AddSpeedy` container. Use when adding to
  `tests\Tests.Unit\CompositionResolutionTests.cs`, registering a new module or port for a screen,
  proving a consumer exists for a `LibrariesModule` registration, writing a hand-transcribed
  registration census, checking which layer a type a screen references actually lives in, or
  diagnosing a port that compiles and is never invoked.
---

Repo: speedmerchants (paths below are repo-relative)

# Speedy UI composed-graph leg

`tests\Tests.Unit\CompositionResolutionTests.cs` in `{SpeedyRepo}`. The smallest
of the four legs (10–25 plan minutes per row; 0 for the two rows with no port) and the one that
catches the defect the other three cannot.

Hub: [[speedy-ui-screen-port]]. Siblings: [[speedy-ui-bunit]] · [[speedy-ui-playwright-axe]].

## What this leg proves, and why compilation does not

Criteria 9.3 / 10.3 / 11.3: *the composed graph resolves every port every screen calls, out of a real
`AddSpeedy` container* — and for UoW-9, *a CONSUMER exists for each `LibrariesModule` registration*.

A registrar that compiles has proven nothing. A missing dependency, a constructor that rejects its
argument, a port bound to a type that cannot be built — every one of those is a clean build and a
container that throws the first time a run needs something. This suite builds a real provider and
pulls every registered port out of it, so a registration that would fail at first use fails here, on
a laptop, in milliseconds.

The precedent that made this a per-screen leg: the `AddSpeedy*` census in this file **proved a
registered-but-never-invoked module is invisible**. A module can be registered, compile, and have no
consumer anywhere, with nothing reporting it.

## Verify every operand against its declaration first

A resolution test is only as true as the names in it, and the first draft of this very section
resolved an `IWorkloadStore` that is declared nowhere. Before writing a line:

```powershell
grep -rn -E 'interface I<Name>\b|class <Name>\b' src
```

```powershell
grep -n -E 'AddSingleton|AddScoped|AddTransient' src\Composition\LibrariesModule.cs
```

`LibrariesModule` registers some things by INTERFACE (`IKeyValueReferenceStore` :199,
`IStepLibraryExporter` :237 → `StepLibraryExporter`, `ITemplateInstaller` :276 → `TemplateInstaller`,
`IBackupService` :294 → `BackupService`) and some as CONCRETE singletons (`WorkloadFileStore` :144,
`StepFileStore` :145, `LibraryFolderService` :165, `SeedManifest` :243). Resolve each by the type the
module actually binds.

## The shape

```csharp
[TestMethod]
public void Provider_BuiltFromTheShippedWebSample_ResolvesEveryLibraryStepsPort()
{
    using ServiceProvider provider = ProviderFor("Web");

    // Interface-bound: assert the concrete type the module binds, not IsNotNull on the interface.
    Assert.IsInstanceOfType<StepLibraryExporter>(provider.GetRequiredService<IStepLibraryExporter>());

    // Concrete singletons: resolve by the concrete type, which IS the registration.
    Assert.IsNotNull(provider.GetRequiredService<StepFileStore>());
    Assert.IsNotNull(provider.GetRequiredService<LibraryFolderService>());
}
```

`ProviderFor("Web")` reads `src\Web\appsettings.sample.json`, which exists. The existing
`EveryShippedSample_*` loops cover `Agent`, `Cli` and `Coordinator` only — the first UoW-9 `.c` leg
adds `"Web"` to those loops, so the authoring host's sample is composed on every run from then on.

Three properties of the existing suite are deliberate and must be preserved:

1. **The configuration is the shipped sample file, read off disk** — not a hand-written fixture. The
   sample is what an operator copies to make a deployment, so a sample that does not compose is a
   deployment that does not start. Rename a binder key and forget the sample, and this suite goes red
   rather than the first container built in anger.
2. **Nothing touches a database.** Every constructor validates its connection string and opens
   nothing; migrators are registered but never run. A container must be buildable on a machine with
   no server, or a host cannot report a configuration fault before it needs one.
3. **`GetRequiredService`, and assert the concrete type.** `IsNotNull` on an interface passes for a
   fake somebody registered by accident.

## The layer a type lives in is part of the operand

vNext's dependency direction is Composition → Infrastructure → Application → Domain; Application
references only Domain. A screen row that ports engine code "into Domain / Application" cannot call a
type that lives in Infrastructure — and vNext's `TokenShapes` (the token grammar) is
`src\Infrastructure\Execution\TokenShapes.cs`. Before dispatch, for every type the row's donor files
reference, find its landed path and check the direction; a wrong layer is a `deviation-blocked` in
the first six minutes (33b hit CS0234 exactly this way).

## Factory registrations are the blind spot

`ValidateOnBuild` cannot see inside a factory. `ICompositeRunProfileSource` is registered through one,
so without an explicit line it would be the single port in the graph nobody resolves, and a mistyped
dependency inside the factory would first surface on a monitor page in a container. **Every screen
port registered through a factory needs its own explicit resolution assertion.**

## Hand-transcribed censuses

Where order or completeness is the property, the list is hand-transcribed *in the same order the
module registers it*, with a comment saying why:

```csharp
/// The break-signal census, hand-transcribed on purpose and in the SAME order the module registers
/// them, because registration order is the order the first breach is decided in.
private static readonly Type[] RegisteredBreakSignals =
[
    typeof(ErrorRateBreakSignal),
    typeof(LatencyBreakSignal),
    typeof(SaturationBreakSignal)
];
```

The cost is honest and must be stated in the row report: **adding a registration without adding it
here does not turn the list red, it makes the list quietly less true.** So a registration and its
census line land in the same change, or the census is worthless. `ArchitectureTests.cs`
`HostProjectNames` carries the same warning for the same reason.

## The consumer census (UoW-9 only)

9.3's second half — *a CONSUMER exists for each `LibrariesModule` registration* — is a different
assertion from resolution. Resolution proves the container can build it; the consumer census proves
something calls it. Shape it as: enumerate the registrations in `src\Composition\LibrariesModule.cs`,
and for each, grep `src\Web` and `src\Application` for an injection site. A registration with no
consumer is either a screen that has not been ported yet (name the row) or dead weight (delete it).

## Which ports each screen needs

`UoW9_Plan.md` §1.1 is the census: every row, its donor page, and **its vNext port cited with a file
and line**. Copy the port list from there, then re-verify each cited declaration and line still holds
([[speedy-ui-screen-port]] step 1) — a plan line number is a statement of intent and drifts.

## Running it

```powershell
dotnet test tests\Tests.Unit\Tests.Unit.csproj --filter FullyQualifiedName~CompositionResolutionTests
```

## Sources

- `tests\Tests.Unit\CompositionResolutionTests.cs`
- `src\Composition\SpeedyServiceCollectionExtensions.cs` (`AddSpeedy`)
- `src\Composition\LibrariesModule.cs` (registrations :142–:294)
- `src\Web\appsettings.sample.json`
- `tests\Tests.Architecture\ArchitectureTests.cs` (the same census warning)
- `{VaultDocsRoot}\speed-merchants\vNext\Design\UoW9_Plan.md` §0.5, §1.1, §2 D8
