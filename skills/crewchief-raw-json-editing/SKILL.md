---
name: crewchief-raw-json-editing
description: >
  CrewChief's raw-JSON view/edit surface — JsonPane, MonacoJsonEditor, and the JsonDefinitionValidator
  unknown-key delta rule that decides whether raw JSON may be saved. Use when working on a raw JSON pane in
  Steps / WorkloadEditor / Activity, when a valid-looking edit is rejected for an unknown key, when Monaco
  falls back to a plain textarea, when wiring a new JSON pane host, or when reasoning about
  JsonExtensionData and MissingMemberHandling in CrewChief.
---

Repo: speed-merchants (paths below are repo-relative)

# CrewChief Raw JSON Editing

CrewChief lets an operator view and edit a step or workload as raw JSON alongside the structured editors.
Three pieces make that safe: `JsonPane` (the host control and commit discipline), `MonacoJsonEditor` (the
editor with a graceful textarea fallback), and `JsonDefinitionValidator` (the one rule for "may this JSON be
saved?").

## When to Use

- Adding or hosting a `JsonPane` on a page.
- "Why was my JSON rejected — the key looks fine?"
- "Why is the editor a plain textarea instead of Monaco?"
- Changing what counts as a valid step/workload definition.
- Reasoning about `[JsonExtensionData]` round-tripping in CrewChief.

## Draft-only commit — typing never writes the model

`JsonPane` (`CrewChief.Web/Components/Controls/JsonPane.razor.cs`) holds a **draft**. Keystrokes mutate the
draft and nothing else; only `TryCommitAsync` (`:118`) validates and writes back to the model.

This is a deliberate divergence from TestAuto's `SmartJsonEditor`, which parses on every keystroke and
swallows failures. Swallow-per-keystroke means a half-typed document is indistinguishable from a broken one,
and the operator gets no single moment where the answer is "yes, this is what you meant". Commit-on-demand
gives exactly one such moment.

## The unknown-key DELTA rule — the part that surprises people

`JsonDefinitionValidator.Validate(...)` (`CrewChief.Data/Services/JsonDefinitionValidator.cs:77`) does not
simply reject unknown keys. It compares against a **baseline snapshot of the unknown keys present when the
pane was opened** (`baselineUnknownKeys`, `:70-75`):

| Unknown key | Verdict |
|---|---|
| Present when the pane opened | **Note** — tolerated (pre-existing forward-compat data) |
| Introduced *during* this edit | **Rejected** |

Both halves matter. `UtilityStepBase` carries `[JsonExtensionData]` (`UtilityStepBase.cs:84`) for
forward-compatibility, which means a misspelling like `sqlScipt` otherwise **saves cleanly and then runs as
a success-reporting no-op** — the worst possible outcome. But blanket-rejecting every unknown key would make
the pane unusable on a file written by a newer CrewChief. The delta rule catches the typo you just made
without punishing you for data you inherited.

> [!warning] Empirically verified Newtonsoft behaviour (13.0.4)
> `MissingMemberHandling.Error` **throws on an unmapped property even when the target type declares
> `[JsonExtensionData]`** — the two do not cooperate. So `StrictSettings` (`:53-56`) can only be used for a
> **manual, non-recursive, top-level** check on `StepFile` / `WorkloadStepEntry`, never as a blanket
> deserialization setting. `WorkloadFile.ExtraParms` is exempt entirely.

`UnknownKeyOccurrence` (`:143-146`) holds a key's baseline **identity** separately from its location,
because for a workload's step bodies the two genuinely differ — the baseline is snapshotted once and reused
by every later `Validate` call, so it must not carry a step's array position.

## Monaco readiness is a retrying probe, not a one-shot

`MonacoJsonEditor` (`:38`, `:69`, `:107`) probes `crewchiefIo.isMonacoReady` and **re-runs the probe on
every render**, not once at `firstRender`. If Monaco never becomes ready, the pane degrades to a plain
`<textarea>` and stays fully usable.

The reason is load order: the page loads Monaco's `editor.main.js`, which only *declares* the AMD module;
the loader then resolves the graph asynchronously. At first render `window.monaco` does not exist yet, so a
one-shot check would permanently and wrongly conclude "no Monaco". (TestAuto hit the same trap from the
other side — see [[testauto-ui-patterns]].)

## Hosts

`Steps.razor:390`, `WorkloadEditor.razor:76` and `:676`, `Activity.razor:306`. A JSON pane participates in
the host page's **single** secret-reveal flag rather than owning its own — see [[crewchief-secrets]]. The
master-password gate applies to raw-JSON panes generally, with the Activity run JSON as the deliberate
exception: that content is already masked at write time.

## Sources

- `CrewChief\CrewChief.Web\Components\Controls\JsonPane.razor(.cs)`
- `CrewChief\CrewChief.Web\Components\Controls\MonacoJsonEditor.razor(.cs)`
- `CrewChief\CrewChief.Data\Services\JsonDefinitionValidator.cs`
- `CrewChief\CrewChief.Data\Services\JsonValidationResult.cs`
- `CrewChief\CrewChief.Web\wwwroot\js\crewchief-io.js`
- `CrewChief\CrewChief.Web\Documentation\raw-json-panes.md`

## Related

[[crewchief-web-ui]] · [[crewchief-step-type-model]] · [[crewchief-file-persistence]] · [[crewchief-secrets]] · [[utility-step-polymorphic-deserialization]]
