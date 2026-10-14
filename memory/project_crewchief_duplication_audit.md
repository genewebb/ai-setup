---
name: crewchief-duplication-audit
description: "2026-07-26 full duplication audit + consolidation: canonical owners (TokenShapes, SecretOutputMasker, StepTypeRegistry.CreateStep, StepLibrarySnapshot, KebabName, ListFilters); 8 bugs fixed; P3 UI extractions partially remaining"
metadata: 
  node_type: memory
  type: project
  originSessionId: e6d8e5b1-4044-498b-a938-4de456f8a54e
  modified: 2026-07-26T23:52:26.164Z
---

Three-sweep duplication audit of CrewChief (token resolvers · masking/heuristics · structural),
followed by an approved full-scope consolidation. Plan file:
`~\.claude\plans\iridescent-roaming-treehouse.md`. Suite went 1712 → 1736 green, 0 compiler warnings.

**Canonical owners established (the only legitimate implementations):**
- Token SHAPE: `CrewChief.Engine\Services\TokenShapes` (regex, $config/$env/$ref prefixes,
  whole-value parsers — IgnoreCase, whitespace-tolerant, first-colon split, UNRESTRICTED ref-type
  grammar — builders, ContainsToken). Web `SecretValueRef` is a thin delegate now.
- Token RESOLUTION: TextTemplater / ParameterResolver / ParameterReconciler only.
  `ValuePreviewService` was REBUILT on the engine resolver via a recording/masking IConfiguration
  decorator (~130-line private mirror deleted); `PowerShellRestExecutor.ResolveAllTokens` (engine-side
  one-hop case-sensitive copy) deleted; `SetupVerification` + StepEditorCard browse/credential paths
  now use ResolveBestEffort (null when still tokened → local/ambient fallback).
- Mask + secret-key heuristic: `SecretOutputMasker` (first3***last3; fragments + `:Key` leaf rule).
  SecretCatalog/SecretsManagement delegate; ConnectionString joined mask-all categories;
  SecretStorageHelper + CLUClientIdProvider masking are documented dead-mirror code.
- Ref→step JSON: `CrewChief.Data\Services\StepLibrarySnapshot` (GetAll-once + per-call, BOTH
  null-Step guarded) — was 7 copies, 3 of which NRE'd on "step": null.
- Step factory: `StepTypeRegistry.CreateStep` (case-insensitive, null for unknown); both pages
  delegate; `StepTypeParityTests` guards registry ↔ UtilityStepTypeInfo ↔ factory (closes BL-B4).
- Kebab name: `CrewChief.Engine\Services\KebabName` (path-traversal guard — 10 copies → 1).
- Param merge: `ParameterReconciler.MergeParameters` (orchestrator + editor delegate).
  StepEditorCard.RunAsync's globals+prompted merge is DIFFERENT BY DESIGN (orchestrator overlays step
  params later) — commented, do not "harmonize".
- Serializer: `UtilityStepConverter.DefaultSettings` + CACHED `Serializer` (was allocating per read).
- List filters: `Components\Pages\ListFilters` generics + ONE `ReconFilterOption` record.
- Transfer leak scan: `TransferSecretScan` (canonical heuristic, `*SecretName` excluded).

**Bugs fixed by the audit:** PowerShellRest hand-rolled resolver; Steps card-paging div-by-zero on
DefaultPageSize=0; EditSectionDialog new-row IsSecret never computed (cleartext password rows);
Steps missing ShapeChanged arm; Steps prompt case-SENSITIVE dict; 3 null-Step NREs; export
plaintext-secret scan blind spots (apiKey/password exact-match only); Configure wizard Review-page
vs preview masking disagreement on clientId* switches (one `IsSecretSwitch` now).

**P3 COMPLETED 2026-07-26 (suite 1742 green):**
1. `CardViewState` (Web\Components\Pages) — ONE view/cols/paging implementation; Steps, Workloads,
   WorkloadEditor, KeyValueReferenceData, Activity (pager half) delegate via thin same-named members
   (markup unchanged). Storage keys standardized dotted `crewchief.<page>.<thing>` with dashed-legacy
   read fallback. ≥1 page-size guard built in.
2. `FilterPersistence` gained LoadStringAsync/SaveStringAsync; Activity's status filter migrated; the
   4 SetViewAsync copies + 5 restore-guard conventions folded into CardViewState.RestoreAsync.
3. `NamingHelpers` (GetNameError w/ noun+example args, BuildCopyName w/ fallback base) — the three
   diverged validators + two copy-name builders delegate.
4. `TokenPromptDialog` shared component; Steps + StepEditorCard swapped their identical markup;
   execution paths stay distinct BY DESIGN (coordinator w/ history/monitor vs inline orchestrator).
5. UtilityOrchestrator alias table now DERIVED from StepTypeRegistry.Registrations (BL-B4 fully
   closed; also fixed the silently-missing Email aliases).

**Deliberately NOT extracted:** the copy/rename/import-export dialog UI-state fields + markup
(~250-line Steps↔Workloads boilerplate). Every drift-prone RULE inside those dialogs is now shared
(NamingHelpers, TransferSecretScan, transfer services, StepLibrarySnapshot); what remains is inert
per-page field/markup plumbing whose extraction is markup surgery with regression risk and no logic
left to drift. Revisit only if a third entity page appears.

**Audit rule (repeat of the session lesson):** when tokens/masks/names misbehave, grep for private
one-off implementations first — the canonical owners above are the only legitimate ones.
