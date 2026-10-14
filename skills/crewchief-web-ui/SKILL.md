---
name: crewchief-web-ui
description: >
  Blazor UI conventions and the step-editor hub for CrewChief.Web. Use when editing .razor/.razor.cs
  components, StepEditorCard per-step-type editors, the Configure wizard, value editors
  (Secret/ServerName/RefData/ServiceName), SegmentedToggle, StepCard/WorkloadCard card grid,
  reorderable parameter rows, list filters, the Templates page, the remote Browse dialog, the
  run-monitor popup, the Icon component, UtilityStepTypeInfo, or render-mode wiring.
---
# CrewChief Web UI (CrewChief.Web)

CrewChief.Web is a standalone **.NET 10 Blazor Web App** (Interactive Server render mode) using
Radzen Blazor + Bootstrap, files-only persistence, Newtonsoft + Serilog, and **zero TestAuto
references** (components were ported and namespace-rewritten). This skill covers the UI conventions
and the mega step-editor. The workload run coordinator and the Activity page live in this project
but are documented in [[crewchief-workload-and-runs]] — reference, don't duplicate.

## Reference files (load on demand)

This file carries the conventions and the decision rules. The component catalogs live in
`references/` and cost nothing until you read one.

| File | Read it when |
|---|---|
| `references/step-editor-card.md` | Adding/changing a step-type editor or the Configure wizard |
| `references/card-grid.md` | Adding a field, pill, or action to `StepCard` / `WorkloadCard` |
| `references/list-filtering.md` | Adding a filter facet or a filter resets unexpectedly |
| `references/sources.md` | You want the underlying source-file list |

## When to Use
- Creating/editing a `.razor` + `.razor.cs` component or wiring `[Inject]` DI into one.
- Working on `StepEditorCard` — the per-step-type field editors, inline Test, or readiness warnings.
- Working on the **Configure step wizard** (switch pages, Review preview, version picker) or the
  remote-editor **Authentication** picker / **Browse…** file dialogs.
- Diagnosing a remote Browse failure on a typed drive-letter path — "A parameter cannot be found
  that matches parameter name 'Directory'" or "Path not found from this remote session" (Drive Map
  letter→UNC translation + the self-diagnosing hint).
- Editing the value editors (five-mode `SecretValueEditor` / `ServerNameEditor` — Literal, Parameter,
  Secret, Reference, Builder — and the six-mode `ServiceNameEditor`, which adds `Pick` first),
  `ValueSourceClassifier`, `ValueBuilder` / `ValueSourceTabs`, the read-only runtime readout
  (`ValuePreviewService` → `ValuePreviewCell` / `RuntimeValueChip`), `RefDataPicker`, or the shared
  `SegmentedToggle` mode selector.
- Working on the `StepCard`/`WorkloadCard` card grid or the card/list view toggle on Steps/Workloads.
- Adding the multi-facet (Name/Description/Tags/Type) filter row on Steps/Workloads, or the `Templates`
  page / Home `FirstRunBanner`.
- Adding sticky page-filter persistence, using the custom `Icon` component, or updating `UtilityStepTypeInfo`.
- Understanding render-mode / logging wiring differences vs TestAuto.

## Code-behind conventions
- Every component is a `.razor` + `.razor.cs` **partial class** (`public partial class Foo : ComponentBase`).
- DI via `[Inject]` **properties** (not constructor). Serilog `ILogger` is injected **directly**
  (`[Inject] public Serilog.ILogger Logger`) — same "no `Microsoft.Extensions.Logging.ILogger`" rule
  as TestAuto, different assembly. `Program.cs` registers it: `builder.Host.UseSerilog()` +
  `AddSingleton<Serilog.ILogger>(Log.Logger)`.
- Lifecycle: `OnInitialized`/`OnInitializedAsync` (one-time), `OnParametersSet` (re-parse when a
  `[Parameter]` changed — guard with a `_previous*`/`_lastEmitted` compare to avoid clobbering local
  edits), `OnAfterRenderAsync(firstRender)` (JS-interop, e.g. restoring sticky filters).
- Implement `IDisposable` to unsubscribe from the run coordinator's `Changed` event.
- Off-render-thread updates marshal through `await InvokeAsync(StateHasChanged)`.
- **Render mode is declared ONCE globally**, not per page: `Program.cs` calls
  `AddRazorComponents().AddInteractiveServerComponents()` and
  `MapRazorComponents<App>().AddInteractiveServerRenderMode()`; `App.razor` sets
  `@rendermode="InteractiveServer"` on `<HeadOutlet>` and `<Routes>`. There is no per-component
  `@rendermode` and no Auto/WebAssembly split. (Prerendering remains on by default; see cross-link
  [[blazor-code-behind]] for the prerender-lifecycle caveats that still apply.)

## The mega `StepEditorCard`

`Controls/StepEditorCard.razor.cs` (~2093 lines) + `.razor` (~2258 lines) is the
per-step-type editor hub. The full per-step-type editor catalog, the shared field
conventions, and the Configure step wizard (`.razor.cs:1480-1956`, `.razor:1415-1843`)
are in **`references/step-editor-card.md`**.

Read it before adding or changing a step-type editor, wiring a new field into an existing
editor, or working on the Configure wizard's switch table and template/values flow.

## Five-mode value editors
`SecretValueEditor` and `ServerNameEditor` both **infer the initial mode from the value string** and
**emit a plain string** (no model/schema change); all token forms resolve at run time via the
engine's `TextTemplater`.

- **`SecretValueEditor.razor`** — modes `Literal` / `Secret` / `Reference` (Data), chosen with a
  `SegmentedToggle` (see below — `RadzenSelectBar` is gone from the app). `SecretOnly=true` hides
  the toggle and forces the Secret form (never drops to literal). Secret mode builds `{{$config:Section:Item}}`; Reference mode builds `{{$ref:type:key}}`.
  Note: the remote-step **"Run As — Remote Credentials"** fields deliberately use the *unrestricted*
  three-mode editor (a plain `SecretValueEditor`, no `SecretOnly`) — Install/Uninstall/Configure
  dropped their former `SecretOnly="true"`, and ServiceControl/AppPool/IisReset gained a new plain
  credential field — so a credential path can be a secret pick, a reference-data entry, OR free text.
  **SetApiKey likewise dropped `SecretOnly` from ALL its fields** (Username, Key, credential pair,
  connection override) — every one is the unrestricted three-mode editor.
  Switching modes clears the value (`OnModeChanged → Emit("")`). Sections come from
  `ISecretCatalog.GetReplaceableSections()`; ref types from `IKeyValueReferenceStore.GetReplaceableTypeNames()`.
- **`ServerNameEditor.razor`** — modes `Secret` / `Reference` / `Text` for a machine/host value.
  Secret mode **delegates to `<SecretValueEditor SecretOnly="true">`**. Reference mode is scoped to
  the `server-names` set (`ReferenceDataSets.ServerNames`). Text mode is a plain input accepting any
  literal or `{{token}}`.
- **`ServiceNameEditor.razor` — the 4-mode sibling** (adds a **Pick** mode): modes
  `Pick` / `Secret` / `Reference` (Data) / `Text` for a Windows service-name value, chosen with a
  `SegmentedToggle<NameMode>`. **Pick** loads the target machine's live services on demand through a
  **parent-supplied `LoadServices` delegate** (`Func<CancellationToken,
  Task<IReadOnlyList<RemoteServiceInfo>>>`) behind a "Load services" button + a filterable
  `RadzenDropDown` (stores the short `ServiceName`). A **`ContextKey`** parameter (target machine +
  Run As credential identity) is compared in `OnParametersSet` and **drops the loaded list when the
  enumeration context changes**, so a stale list is never offered for a different machine. Secret mode
  delegates to `<SecretValueEditor SecretOnly="true">`; Reference/Text mirror the other editors; the
  initial mode is inferred from the value (blank → Pick). Used by the **ServiceControl** branch of
  `StepEditorCard` — it **replaced the old inline Load-services button + dropdown/text swap**, with the
  card supplying the delegate via `LoadServicesForPickerAsync(svcStep, ct)`
  (→ `IRemoteServiceInventory.GetServicesAsync` over the resolved target + Run As credential) and the
  `ContextKey` via `ServiceEnumerationContextKey(svcStep)` (target|user|password|secret).
- **Token parse/build**: `{{$config:...}}` is centralized in `Services/Secrets/SecretValueRef.cs`
  (`TryParse` / `Build` / `IsSecret`, regex-anchored, entry may contain colons). The `{{$ref:...}}`
  form is parsed/built through **`TokenShapes`**, the single owner of the `{{...}}` shapes — `TokenShapes.BuildRef` / `TryParseWholeRef`, consumed by `ValueSourceClassifier` and `TokenComposition`. *Corrected 2026-09-09: this previously said the form was parsed inline in each editor via a local `RefRegex` + `BuildRef`. `RefRegex` now returns ZERO hits anywhere in the repo — the shapes were centralised because an audit found 3 copies of the token regex, 5 of `$config` and 7 mutually incompatible `$ref` parsers. See [[crewchief-token-replacement]].*
- **Catalogs**: `SecretCatalog` (`GetSections`/`GetReplaceableSections`/`GetSectionsForPage`/
  `GetItems`/`GetMaskedValue` — masking reveals 3+3 chars) reads sections from
  `SecretSectionRegistry` (metadata under `SecretSchema.MetaPrefix`, `IncludeInReplacements` is a
  hard kill-switch) and item leaves from the loaded Local Secrets config.
- This picker is a **convenience, not a restriction** — it appears on sensitive fields to make
  choosing a secret easy; raw literals and any `{{token}}` remain valid in token fields by design.
  Do not widen the picker or add literal-secret enforcement — see memory
  [[project_crewchief_secret_picker_convenience_only]].

## `SegmentedToggle` (`Controls/SegmentedToggle.razor` + `.razor.css`, `SegmentedOption.cs`)
The **app-wide mode-selector convention**: a generic pill bar (`SegmentedToggle<TValue>` with
`IReadOnlyList<SegmentedOption<TValue>> Options`) that replaced `RadzenSelectBar` everywhere
(zero `RadzenSelectBar` hits remain in CrewChief.Web). Each `SegmentedOption<TValue>` record
carries the value, label, an optional Material icon, an optional **accent CSS class**
(`cc-seg-literal` / `cc-seg-secret` / `cc-seg-ref` — the active pill lights up in that accent),
and an optional tooltip. Markup: `.cc-segbar` container with `.cc-seg` pill buttons.
Users: `SecretValueEditor` (Literal/Secret/Reference), `ServerNameEditor` (Secret/Reference/Text),
`EditSectionDialog` (Pick/Custom). Convention (per user preference): independent **on/off** toggles
stay `RadzenSwitch`; **mutually-exclusive modes** use `SegmentedToggle`.

## `RefDataPicker` (`Controls/RefDataPicker.razor`)
An **optional** filterable dropdown assist for a free-text field. It renders **only when** its named
KV reference-data type has entries (`@if (_options.Count > 0)`); otherwise it renders nothing and the
field's own text input stays the always-available fallback. `UseValueAsValue` selects whether a pick
stores the entry **value** (e.g. a GUID) or its **key** (a name). Used for CLU Strategy/Entity and
ConnEx Resource Id.

## Card grid — `StepCard` / `WorkloadCard`

`Controls/StepCard.razor(.cs)` and `WorkloadCard.razor(.cs)` — layout, the fields and
pills each card renders, action buttons, and how values are threaded in from the host
page: **`references/card-grid.md`**.

Read it when adding a field, pill, or action to a card, or when a card value is not
reaching the grid. Run-monitor behaviour lives in [[crewchief-workload-and-runs]].

## Filters — sticky state and multi-facet filtering

localStorage-backed sticky filters and the multi-facet filter/sort model shared by the
Steps and Workloads lists: **`references/list-filtering.md`**.

Read it when adding a facet, changing what persists across sessions, or when a filter
resets unexpectedly. Also memory [[reference_crewchief_sticky_filters]].

## Templates page & Home banner
- **`Templates` page** (`Components/Pages/Templates.razor(.cs)`, route **`/templates`**) — listed in
  `NavMenu` **after "Reference Data"** with `Icon Name="view_module"`.
- **`FirstRunBanner.razor`** (`Controls/`) — the Home (`/`) first-run banner (used by `Home.razor`).

## Icons & step-type visuals
- **Custom `Icon` component** (`Components/Icon.razor` + `.razor.cs`): renders
  `<span class="material-icons @Class" style="@Style" @attributes="AdditionalAttributes">@Name</span>`.
  It is **not** `Radzen.Icon`. `Name` is `[EditorRequired]`. (Material Icons font is linked in
  `App.razor`.)
- **`Helpers/UtilityStepTypeInfo.cs`** — single source of per-step-type visual metadata:
  `GetIcon` / `GetDisplayName` / `GetDescription` / `GetHelpSlug` (→ `/help/step-guides/<slug>`) /
  `GetAccentColor` / `GetBgColor`, plus `AllTypes` (`UtilityStepTypeInfo.cs:185-188` — the 22 canonical
  type keys the "Add Step" picker offers, now including `WebSiteStep`, `CheckPortStep` and `TeamsStep`).
  All these switch blocks + `AllTypes` **must stay in sync**
  when a step type is added — see [[crewchief-adding-a-step-type]].
  - The three newest arms deliberately reuse **already-whitelisted** Material Symbols glyphs — `dns`
    (CheckPort), `language` (WebSite), `chat` (Teams) — rather than a more apt but unverified name. An
    unmapped icon name renders as literal text, so "close enough and known-good" beats "perfect and
    unchecked"; see [[blazor-icons]].
  - `"WEBSITE" or "WEBSITESTEP" or "SITE"` is the **second** three-alias arm in this file, after curl.
- **The curl key is `"CURL"`, not `CurlStep`.** `AllTypes` reads
  `"SQL", "PowerShellStep", "CommandLineStep", "CLU", "HTTP", "CURL", "ConnExStep", …`
  (`UtilityStepTypeInfo.cs:168`) — curl is the one entry spelled as the short alias. It matters because
  every metadata switch in this file pivots on `type.ToUpperInvariant()` against arms that list **both**
  forms (`"CONFIGURE" or "CONFIGURESTEP"`), **except curl**, whose only arm is `"CURL"`
  (`:20`, `:45`, `:70`, `:98`, `:123`, `:148`). Feed it `"CurlStep"` and every lookup silently falls to
  the default arm — generic `play_circle` icon, `#f8f9fa` background, no description. `StepDescriptionSeeder`
  keys the `step-descriptions` reference set off `AllTypes` verbatim, so the wrong key also mis-keys that set.
  - Step **construction** is *not* affected: `StepTypeRegistry` (`CrewChief.Engine/Steps/StepTypeRegistry.cs:47`)
    is case-**insensitive** and registers `"curlstep", "curl"` as aliases (`:59`), so
    `Steps.razor.cs:635` / `WorkloadEditor.razor.cs:550` (`StepTypeRegistry.CreateStep(type) ?? new CommandLineStep()`)
    would still build a real `CurlStep`. The damage is confined to UI metadata + the description seed key.

## Cross-links
- [[crewchief-workload-and-runs]] — WorkloadRunCoordinator + Activity page (documented there).
- [[crewchief-adding-a-step-type]] — the full checklist when introducing a new step type.
- [[crewchief-reference-data]] — KV reference sets (server-names, DriveMap, the two-tier configuration-template/configuration-values pair) + ConfigurationSwitchCatalog.
- [[crewchief-secrets]] — the secrets store the SecretValueEditor picks from.
- [[crewchief-http-curl-split]] — why HttpRequestStep and CurlStep are separate editors.
- [[blazor-code-behind]], [[blazor-icons]], [[testauto-ui-patterns]], [[custom-parm-editor]] — TestAuto originals these were ported/trimmed from.

## The value-source classifier and the runtime readout

Three surfaces sit behind the five-mode editors:

- **`ValueSourceClassifier`** - the single ordered value-to-source decision, **deliberately one copy** so
  the editor's tab choice and the parameter-grid row colours can never disagree. Two classifiers would
  drift, and the disagreement would be invisible.
- **`ValueBuilder` / `ValueSourceTabs`** - compose a value out of segments plus filter chains (see
  [[crewchief-token-replacement]]).
- **The read-only runtime readout** - `ValuePreviewService` to `ValuePreviewCell` / `RuntimeValueChip`.
  It **masks secrets**, uses a **CSS-only popover so it survives a reconnecting circuit**, and **copies
  exactly what is displayed** (never the underlying secret).

That popover choice is deliberate: a JS-driven popover dies with the circuit, and the readout is most
wanted precisely when a run is in trouble.

## List filtering delegates to shared helpers

The per-page filter statics are now **thin delegates**. The convention:

> The page-level public statics **stay** - they are the tested seams - but their bodies delegate to shared
> generic helpers.

| Helper | Covers |
|---|---|
| `ListFilters` | `ByTags` / `ByText` / `ByValues` / `ByReconciliation` |
| `FolderFilter` | `null` = all, empty string = root, a path = that folder **and descendants** - with a folder-plus-slash suffix check so `matching-archive` is not a child of `matching`. See [[crewchief-library-folders]] |
| `TagAssignment` | add-only Ordinal union that **must return a NEW list**, or a bound `RadzenDropDown`'s selection goes stale |

That last one is a Radzen binding trap, not a style preference - mutating the existing list in place
leaves the dropdown showing a selection that no longer exists.

## Sources

Full source-file list: **`references/sources.md`**.
