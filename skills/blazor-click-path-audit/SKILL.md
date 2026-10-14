---
name: blazor-click-path-audit
description: >
  Traces every interactive Blazor touchpoint through its full state-change
  sequence to find bugs where each handler works in isolation but the combined
  effect is wrong — one call silently undoing another, a guard that never fires,
  a parent re-render discarding child edits. Use when a button "does nothing",
  when systematic debugging found no bug but the UI is visibly broken, after
  refactoring shared component or service state, or after changing a
  SaveToConfiguration / LoadFromConfiguration round-trip.
---

# Blazor Click-Path Audit

Finds the bugs static reading misses: state interaction side effects, ordering
races, and handlers that quietly cancel each other out.

## The Problem This Solves

Ordinary debugging asks:

- Does the handler exist? (missing wiring)
- Does it throw? (runtime error)
- Are the types right? (data flow)

It does **not** ask:

- Does the final UI state match what the button label promises?
- Does call B silently undo what call A just did?
- Does a parent re-render discard what the child just wrote?

A real instance from this codebase: a copy-workflow path set `Code = ""`, so the
later `Code ??= GenerateCode()` never fired — `""` is not `null`. Every method
worked. The result was a duplicate-save 8603 loop. No exception, no missing
wiring, no type error.

## Scope Control

This audit is expensive. Pick a scope:

| Scope | When |
|---|---|
| Single component | A specific control is misbehaving |
| Single page | New page, or a user reported a broken button |
| Service-focused | After changing a scoped/singleton service — audit every consumer |
| Full app | Pre-release, or after a large refactor |

For a full-app pass, split by page across parallel agents — but **the state map
(Step 1) must complete first and be handed to every other agent.** Without it,
the audit cannot see the silent resets, which is the whole point.

Suggested CrewChief split: `StepEditorCard` per-step-type editors; the multi-page
Configure wizard (`WizardState`); `WorkloadEditor`; the Activity page; the value
editors (`SecretValueEditor`, `ServerNameEditor`, `ServiceNameEditor`,
`RefDataPicker`); the dialogs (`FileBrowserDialog`, export/import).

## Step 1 — Build the state side-effect map

Before auditing any touchpoint, enumerate everything that writes shared state.

For each of:

- **Component fields/properties** mutated by handlers
- **Injected scoped or singleton services** holding state between calls
- **`[Parameter]` properties** the parent re-assigns on re-render
- **`[CascadingParameter]`** values
- **The config round-trip** — `SaveToConfiguration` / `LoadFromConfiguration`

record what it sets *and what it clears as a side effect*:

```text
SERVICE: WizardState
  SetProduct(code)      -> sets {ProductCode}  RESETS {SwitchValues, SelectedVersion}
  LoadTemplate(name)    -> sets {SwitchValues, TemplateName}
  Reset()               -> resets everything

COMPONENT: StepEditorCard
  OnParametersSet()     -> re-reads Step into local edit fields   <-- discards unsaved edits

DANGEROUS RESETS (clears state it does not own):
  WizardState.SetProduct -> clears SwitchValues (owned by the switch page)
```

The `DANGEROUS RESETS` list is the deliverable. Most bugs in this class become
visible the moment it exists.

## Step 2 — Trace each touchpoint

For every `@onclick`, `@onchange`, `EventCallback`, `OnValidSubmit`, and `@bind`
on the target surface:

```text
TOUCHPOINT: [Save] in WorkloadEditor.razor:214
  HANDLER: OnSaveAsync -> {
    1. await Store.SaveAsync(model)      sets {persisted}
    2. State.Reset()                     RESETS {model}      <- CONFLICT
    3. StateHasChanged()
  }
  EXPECTED: saved, editor still shows the saved values
  ACTUAL:   saved, editor blanks
  VERDICT:  BUG - Sequential Undo
```

Check every pattern below.

### Pattern 1 — Sequential Undo

A handler sets a value, then calls something that resets it as a side effect.
Requires the Step 1 map to see.

### Pattern 2 — Async ordering / missing await

```csharp
private async void OnClick()      // async void: exceptions unobservable
{
    _ = LoadAsync();              // not awaited
    _isLoading = false;           // runs before LoadAsync finishes
}
```

Also: two awaits writing the same field, where the final value depends on which
completes first.

### Pattern 3 — Stale capture across an await

```csharp
var snapshot = _items;            // captured before
await Service.RefreshAsync();     // _items replaced during
Save(snapshot);                   // writes the pre-refresh copy
```

Also the classic loop-variable capture in `@foreach` with a lambda handler.

### Pattern 4 — Missing transition

The label promises something the handler never does: validates but never
persists; sets a flag but never calls the API; mutates state but omits
`StateHasChanged()` so the UI never reflects it. In Interactive Server, a
mutation outside an event handler (a timer, a background callback) **must** be
marshalled with `InvokeAsync(StateHasChanged)`.

### Pattern 5 — Conditional dead path

A guard that is always false at that point:

```csharp
model.Code = "";                  // upstream
model.Code ??= GenerateCode();    // never fires - "" is not null
```

Check `??` / `??=` against **empty string** as well as null. Check
`if (x != null)` where `x` is a non-nullable value type. This pattern produced
the duplicate-save 8603 loop.

### Pattern 6 — Parameter interference

The parent re-renders and re-assigns a `[Parameter]`, so `OnParametersSet`
overwrites the child's in-progress edits. Symptom: typing works until something
unrelated triggers a parent render, then the field reverts.

A known instance: an overwrite guard was needed on `LubcRequestAttributes` for
exactly this reason — an unguarded assignment discarded values written earlier.

### Pattern 7 — Round-trip asymmetry (Blazor-specific, high value)

Where an editor has `SaveToConfiguration` / `LoadFromConfiguration`, verify they
are **exact inverses**:

- Every field written by Save is read by Load, and vice versa
- A field added to the editor but not to Save is silently lost
- A field read by Load but never written by Save reverts to default on reload

Method: list both field sets and diff them. An asymmetry here is a data-loss bug
that no test of either method alone will catch.

## Step 3 — Report

```text
CLICK-PATH-NNN  [CRITICAL|HIGH|MEDIUM|LOW]
  Touchpoint: <label> in <file>:<line>
  Pattern:    <one of the seven>
  Trace:
    1. <call> -> sets {field}
    2. <call> -> RESETS {field}   <- CONFLICT
  Expected:   <what the label promises>
  Actual:     <what happens>
  Fix:        <specific change>
```

Every finding needs a file, a line, and a concrete trace. "Might have a race" is
not a finding.

## When NOT to Use

- API-level bugs (wrong response shape, missing endpoint) → `superpowers:systematic-debugging`
- Styling and layout → visual inspection
- Server-side exceptions → `silent-failure-hunter`, then the platform logs

## Related Skills

- `crewchief-web-ui` — component inventory and conventions for the surfaces above
- `blazor-code-behind` — the `.razor` / `.razor.cs` split, lifecycle, and the
  prerender `ObjectDisposedException` / `InvokeAsync` marshalling rules
- `testauto-ui-patterns` — the equivalent surfaces on the TestAuto side
- `superpowers:systematic-debugging` — run first; this catches what it misses
- `silent-failure-hunter` — the server-side sibling of this audit

---

Adapted from ECC (MIT, © 2026 Affaan Mustafa) — <https://github.com/affaan-m/ECC>
