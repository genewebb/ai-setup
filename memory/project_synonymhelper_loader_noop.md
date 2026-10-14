---
name: project_synonymhelper_loader_noop
description: FIXED 2026-07-13 — SynonymHelper loader filter + Matching-export parser + per-file hardening; VariantGenerator rule 5 (synonym swap) now works
metadata: 
  node_type: memory
  type: project
  originSessionId: 6b63293e-52a8-4178-a1a7-d5f173eb58a3
---

`TestAuto.Shared\Helpers\SynonymHelper.cs:26` filters manifest resources with `n.Contains("SynonymList.") && n.EndsWith(".json")`, but the embedded lists ship under the PLURAL folder `SynonymLists\` → manifest names like `TestAuto.Shared.SynonymLists.Address.json`. The literal substring `"SynonymList."` (period after `List`) never occurs in `"SynonymLists."` (the char after `SynonymList` is `s`, not `.`), so the filter matches **zero** resources, `_synonyms` stays empty, and every `ApplySynonyms(...)` call returns its input unchanged. Net effect: `VariantGenerator.ApplyRule` rule **5 (synonym swap)** silently does nothing for `CloneAndMutateScenario`.

Discovered 2026-07-12 during a skill-audit Mode 6 corpus review (not while working the code). Surfaced to the user as informational only — the speed-merchants repo is the audit's read-only scan target, so no fix was applied.

**Likely fix:** change the filter to `n.Contains("SynonymLists.")` (or match `".SynonymLists."`), and note the dictionary key is then the full dotted manifest name (`TestAuto.Shared.SynonymLists.Address`), so `ApplySynonyms(category, …)` lookups keyed on a bare attribute/category name would also need reconciling. Verify against `TestAuto.Shared\TestAuto.Shared.csproj:11-33` (the six EmbeddedResource lists: Address, City, Country, DateOfBirth, Email, StreetAddress).

The [[skill-audit-with-update]] skill `testauto-record-transformation` now documents this loader reality accurately.

**FIXED 2026-07-13** (during [[project_net10_profisee_upgrade]] follow-up). Three things done in `SynonymHelper.cs`: (1) loader filter already corrected to `.Contains(".SynonymLists.")` so the 6 files now load; (2) **A1 parser** — all 6 files are actually Profisee Matching synonym-file EXPORTS (not flat string arrays), so the constructor now parses that schema via `JToken.SelectTokens("$..Synonyms")` recursive descent, handling BOTH layouts (legacy `Synonyms=[{Name,Term}]` e.g. Address.json AssemblyVersion 2.5.7.0, and current `Synonyms.MatchingSynonym[]` with nested `Identifier.Name`+`Term`) plus wrapped/unwrapped root and single-or-array `MatchingSynonymType`; extracts `Identifier.Name`(or `Name`) + non-empty `Term`. (3) **Part B** — each file wrapped in try/catch + `Log.Logger.WarningWithTag` so one bad file can never abort the loader (it ran inside scenario construction → a throw cascaded into the "scenario resolution failed" startup warning). Verified term counts: Address 576, Country 57, DateOfBirth 27, StreetAddress 21, Email 20, City 11. Category key is still the bare filename segment (Address, City, …) matching attribute names passed to `ApplySynonyms`. This also cleared the pre-existing `MatchingSynonymFile` deserialization warning noted in [[project_net10_profisee_upgrade]].
