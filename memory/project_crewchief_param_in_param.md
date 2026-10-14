---
name: crewchief-param-in-param
description: "2026-07-24 ParameterResolver resolves {{Param}}-in-param values (any order, cycle guard) + $ref param values; unknown tokens fail fast; 2026-07-26 the Web Effective Value preview finally resolves them too (all-or-nothing, secrets masked, cycle shown not thrown)"
metadata: 
  node_type: memory
  type: project
  originSessionId: 777a7eea-fcad-44ae-9256-e6de518573d5
  modified: 2026-07-26T21:11:24.803Z
---

CrewChief `ParameterResolver.ResolveSpecialParameterValues` was extended (2026-07-24) beyond the
$config/$env two-hop: parameter VALUES may now reference **other parameters** (`installed_name =
"Profisee Server {{version}}"`), resolved recursively against the merged global+step set,
memoized, definition-order-independent, with cycle detection
(`CircularParameterReferenceException : UnresolvedParameterTokenException`, so the orchestrator's
existing catch handles it). Two-phase: resolve-all-then-write-back, so a throw leaves the caller's
dictionary intact and ConnEx JSON escaping applies exactly once (chained values embed RAW memoized
results). Also fixed: `{{$ref:...}}`-only param values used to leak literally (the editor's
Reference Data pill produced exactly that shape).

**Behavior changes to remember:**
- An unknown plain `{{token}}` in a param value now THROWS (used to leak literally, silent).
- A self-mapping "pass-through" param (`RunLabel = {{RunLabel}}`) is now a hard cycle error — the
  21_WorkloadTokens.md example that showed it was fixed.
- The [[crewchief-token-replacement]] skill has since been updated and now documents param-in-param
  correctly (verified 2026-07-26).

**Web preview lagged the engine (fixed 2026-07-26).** `CrewChief.Web/Services/ValuePreviewService.cs`
`Describe()` took only the value — no sibling-parameter context — so the "Effective Value" column
echoed `Profisee {{profisee_version_number}} (Profisee)` verbatim with a "Run time" chip even though
the engine resolves it. `Describe(value, siblings)` now mirrors ParameterResolver (recursive,
memoized, order-independent, case-insensitive), resolves embedded `$config` MASKED / `$env` / `$ref`,
and is **all-or-nothing**: any unanswerable token → raw text + "Run time" (never a half-substituted
string). A cycle is RECORDED (shown as `circular reference: a -> b -> a` warning), not thrown — a
preview renders on every keystroke. Siblings supplied by `WorkloadEditor` (globals) and
`StepEditorCard` (`BuildResolutionParameters()` = globals + step params).
**Lesson: when the engine gains a resolution capability, the design-time preview is a second
implementation that must be updated with it.**

**Third instance (fixed 2026-07-26): the Install/Configure command previews.** StepEditorCard's
`ResolveTokenValue` was ANOTHER weak resolver — whole-value `$config`/`$ref` only, params left
literal — so a revealed preview showed `{{profisee_admin_user}}` instead of the value. Both preview
builders now do run-equivalent resolution: `BuildResolvedPreviewParameters()` (merged
globals+step params → `ResolveSpecialParameterValues` on a copy, fall back to raw on throw) then
`ParameterResolver.ResolveBestEffort` per value (unresolvable tokens stay visibly literal). Secret
switches mask with the shared first3***last3 form (was `********`), and the mask heuristic widened
to catalog-IsSecret OR `SecretOutputMasker.LooksLikeSecretKey(switchName)`. Builders are PUBLIC
test seams (strong-name signing precludes InternalsVisibleTo — established convention).
**Audit rule: grep for private one-off `{{...}}` resolvers when tokens misbehave — TextTemplater /
ParameterResolver / ParameterReconciler are the only legitimate implementations.**

Same session: WorkloadEditor global-params and StepEditorCard step-params tables got move up/down
buttons (organizational only). Both dictionaries are rebuilt fresh on move/remove/rename so
enumeration order == display order == persisted JSON order; `RenameParameter` now keeps row
position instead of jumping to the end.
