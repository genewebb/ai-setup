---
name: project-crewchief-value-builder
description: CrewChief Builder value source (4th pill) — shipped 2026-08-24, composes Secret/RefData/Text/Date segments with token filters
metadata:
  type: project
---

CrewChief value editors gained a **4th pill, Builder**, beside Secret / Reference Data / Text. It composes segments from those catalogs plus the clock (`$now`/`$utcnow`/`$today`), applies the engine's pipe filters, and writes the token string. Shipped 2026-08-24; build 0-error, suite 3158 → **3232** tests.

**Key architecture fact:** the editors store **a plain string** and *infer* the pill from it. Builder is a pure authoring surface — **no schema, no migration, no engine change**. A value built in the UI and the same value hand-typed are identical on disk.

Pieces:
- `CrewChief.Engine/Services/TokenComposition.cs` — `TryParse`/`Build`/`Validate` over `CompositionSegment(SegmentSource, First, Second, Filters)`. `SegmentSource = Text|Secret|Reference|Clock`.
- `CrewChief.Engine/Services/TokenFilters.cs` — added `Describe`/`DescribeAll` (drives the filter picker off the existing `Arity` table, with a parity test), promoted `Unescape`/`SplitUnescaped` to public, added `EscapeArgument`.
- `CrewChief.Web/Components/Controls/ValueBuilder.razor` — inline stacked segment rows, filter chips with arity-typed argument inputs, footer = `=` preview **then** raw token string.
- Pill on `SecretValueEditor`, `ServerNameEditor`, `ServiceNameEditor`. NOT `ShareCredentialEditor` — its pill row picks share *type*, not a value source; it inherits via inner `SecretValueEditor`s.

**Two traps that shaped the design, worth remembering:**
1. `TokenFilters` has `Unescape` but had **no `Escape`**, and `Unescape` deliberately keeps unknown escapes so `C:\Temp` survives. So escape/unescape is **asymmetric** — `EscapeArgument(Unescape(x)) != x` in general.
2. `TokenShapes.SplitFilters` **trims** source (:144), bare filter name (:152), and name-before-colon (:157). So `{{ $now | addDays:7 }}` rebuilds tighter than typed.

Both are neutralised by the same rule: `TryParse` **rebuilds each token and byte-compares against the source**, returning false on any difference. False falls back to Text with the raw string intact — a conservative false is safe, a wrong `Build` silently rewrites the operator's value.

Docs: `Design_ValueBuilder.md` + `Plan_ValueBuilder.md` in `Q:\Work\Work\99 Documentation\CrewChief\`. Design's **Addendum** section overrides the plan where they conflict. Help docs updated: `21_WorkloadTokens.md`, `36_OpsSecretReplacement.md`, `05_CookbookStepBuilder.md`.

Known cosmetic gap: the `ddd, dd MMM yyyy` date preset emits `date:ddd\, dd MMM yyyy` (escaped comma) — resolves identically but isn't the doc-spelled form. See [[project_crewchief_token_filters]], [[reference_radzen_light_text_button_invisible]].
