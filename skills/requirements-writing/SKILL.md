---
name: requirements-writing
description: >-
  Authors and reviews Speedy requirements using the shared RequirementDesign standard,
  canonical YAML, the JSON schemas, the fictional sample package, and the reqtools.py tooling.
  Use when defining a feature, documenting existing application behavior, turning inspected
  Speedy work into proposed requirements, recording inclusion decisions, improving acceptance
  criteria, applying answers to requirement questions, computing a revision digest, validating
  the corpus, or aligning templates and samples with the standard. Does not implement the
  application or treat existing code as an approved product decision.
---

Repo: speedmerchants (paths below are repo-relative)

# Requirements Writing

Create clear, reviewable requirement definitions with evidence, explicit decisions, and useful questions. Preserve the distinction between what exists, what is intended, and what has been verified.

## Load the current authority

The shared source is `{VaultDocsRoot}\speedy\requirements\`. In Obsidian's Work vault its relative path is `99 Documentation/speedy/requirements/`. Read with the filesystem or the Obsidian connector; **write every vault file through Obsidian's Local REST API**, never with a direct file write, because Obsidian's index over the SMB share is blind to direct writes:

```text
pwsh "{ClaudeHome}\bin\Write-AIFile.ps1" -Path "{VaultDocsRoot}\speedy\requirements\<path>" -Source <local file>
```

Never embed credentials in this skill or ask the user to paste a token into chat; the script reads the key itself.

Read `RequirementDesign.md` at the start of an authoring task, then the matching template in `templates/` and the relevant sample under `RequirementDocumentExample/` (its `README.md` says which sample shows what). Read `schemas/canonical-form.md` when hashing and the schema for the artifact type when checking structure. These files own the rules; this skill is an operating guide, not a second standard.

Read their actual status. A draft standard, sample, passed schema check, or a request to write requirements is not an approval. If a template contradicts the current standard, preserve the standard and report or correct the template within the task's scope. Do not silently substitute an archived format. If required sources cannot be read, identify the specific gap and continue only work that does not depend on it.

For the reference locations, the artifact selection guide, and the tooling commands, read [references/authoring.md](references/authoring.md). For the checks every acceptance criterion passes before hand-off, read [references/criteria-checks.md](references/criteria-checks.md). Inspect only the source material relevant to the requested boundary; this skill does not require a full repository survey for every edit.

## Use the tooling, never a hand-typed digest

`tools\requirements\reqtools.py` implements the standard and the canonical form:

```text
python tools\requirements\reqtools.py digest --write <artifact.yaml>
python tools\requirements\reqtools.py validate "{VaultDocsRoot}\speedy\requirements"
python tools\requirements\reqtools.py render <feature.yaml> <view.md>
python tools\requirements\reqtools.py backlog "{VaultDocsRoot}\speedy\requirements"
python tools\requirements\reqtools.py build-examples "{VaultDocsRoot}\speedy\requirements"
```

Run `validate` after every edit and before every hand-off; zero errors is the floor, and the report lists which semantic checks ran. `digest --write` is the only way a `revision` is set. `render` regenerates a read-only Markdown view; never edit a view. `build-examples` derives the sample variants from the base sample; run it only when editing the sample package. If Python, PyYAML, `jsonschema` or `referencing` are missing, say so and stop short of any claim that needs them.

## Choose the requested work

- **Template/example work:** use fictional content with the `EXAMPLE` DOMAIN and `mode: example`. Do not produce live Speedy decisions or register example IDs in the live ledger. Edit the base sample and rebuild the variants; never hand-edit a derived variant.
- **Existing behavior:** write application-owned `SRC-`/`BEH-` observations and inventory coverage. Distinguish code inspection, test assertions, execution, and reported behavior; mark inferences; name defects and inspection limits.
- **Speedy definition:** keep the permanent candidate's inclusion decision separate from the target. A wholly new target uses disposition `NEW` with its no-donor basis and says in `not_applicable` why it has no candidate.
- **Review or answer application:** work in the owning YAML; check affected criteria, metrics, constraints, mappings, and consumers. Report findings separately when asked to review rather than edit.

Before adding a record, search the active corpus for an existing owner. Keep existing IDs. Read the current manifest and ID events; request allocation through the coordinator and its reserved ranges. Do not fabricate a reservation, hand out already used IDs, or edit the coordinator's files from an application-only assignment.

## Define behavior and expose choices

Establish the actor, outcome, trigger, scope, inputs, state effects, failures, and meaningful exclusions. Ask the owner focused questions as choices arise. Continue useful independent drafting while awaiting answers; leave consequential uncertainty visible and blocking.

Record existing behavior once, in its source record. Compare application variants item by item: no application and no existing Speedy implementation automatically wins. Keep routine current decisions and rationale with their owner; use a separate ADR when the standard calls for one. Do not carry an obsolete decision trail into current requirements.

Write each obligation with its acceptance, plausible counterexample, and verification plan. State every case a criterion needs inside the criterion, with expected results and fixtures; a pass/fail rule never lives only in a Markdown brief. Make each fixture satisfiable on its own. Use observations that could actually expose an incorrect implementation, including persisted state. A verification plan is a plan; do not claim it ran. Before a criterion goes to a planner, run the ten checks in [references/criteria-checks.md](references/criteria-checks.md): fixture figures carry their source, absence searches are probed against the fixture, name collisions are profiled, criteria sharing a fixture are checked pairwise, no criterion casts a wider net than its requirement, expected strings come from the component that produces them, the rule is observable through the design's surface, a value reused in several grammars has its allowed grammar stated, input-shape assumptions live in the term, and displayed or numeric values pin culture and precision. Put measured targets in metrics with their conditions. An unknown threshold stays unresolved through `unresolved_by`; a plausible default or zero does not resolve it.

Use the current standard's field names, ID grammar, `ARTIFACT-ID#key` local references, relationships, inclusion/disposition/treatment rules, and type-specific gates. Apply a shared rule with a requirement-level `applies` relation that pins the contract's revision, and let that requirement state its own obligation and conditions. Readiness blockers propagate to whole owning artifacts and their explicit prerequisite consumers; `related` links and `provided_by` add no prerequisite edge. Fill `not_applicable` with a reason for every required section that truly does not apply.

Keep implementation observations and executed evidence outside the normative hash as the canonical form specifies. Report partial implementation from inspected evidence without claiming verified acceptance. Preserve earlier verification attempts and identify the implementation each attempt actually exercised.

## Apply answers without losing their effect

Transfer an answer supplied in chat to the question's owning artifact, with attribution, date and source. Keep it `ANSWERED_PENDING_APPLICATION` and blocking until every affected definition, criterion, metric, decision, and reference is updated and checked. The generated backlog is read-only.

After checking application, remove the question from the active list and use the coordinator's retirement workflow in `ids.yaml`. Do not confuse resolving a question with approving the changed feature. Changed normative content or binding contracts requires the review and approval specified by the standard.

## Check, save, and hand off

Separate structural checks, implemented semantic checks, human judgment, and approval. Run `validate`, confirm the criteria checks were run, then review against the standard's Q1–Q10 gates by hand: reference ownership, all included behavior, acceptance and verification coverage, source support, unresolved choices, consistency with constraints. State precisely which checks were run by the tool and which by hand. A passing validator does not prove any of the human gates.

Independent review is by Gene, or by Claude Code in a clean session (a fresh session given the review prompt and nothing else, never the authoring session); Claude is the only tool reviewer, recorded as `tool: Claude`. The review record's `given` line must say "clean session"; the validator rejects a tool review by any other tool on a live artifact, and a Claude review whose `given` does not say clean session. Approval belongs to Gene or an explicitly scoped delegate. Leave new or changed records `DRAFT`/`REVIEW` until the applicable gates and actual approvals are met; a later material edit changes the digest and the validator reports the approval stale.

Before saving, re-read the affected files and reconcile unexpected edits; another author or tool may have written concurrently. Write through the Obsidian API and verify saved contents by hash. Edit authoritative YAML and regenerate read-only views with accurate provenance; do not answer questions in generated Markdown. Keep archive, examples, and templates out of live discovery and readiness counts.

Finish with links to the changed artifacts, remaining questions, the validator's result, checks actually performed by hand, and the next required review. Do not assign priority, run application or `.loop` work, change app code, or commit merely because requirements were requested.
