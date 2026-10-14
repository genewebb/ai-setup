---
name: project_speedy_requirements_amendment_protkey_2026-09-20
description: "How a Speedy requirements amendment is built (never edit live artifacts), and the concurrency + cycle traps found on 2026-09-20"
metadata: 
  node_type: memory
  type: project
  originSessionId: e172ab42-8007-4930-84a6-9624ddbbd700
  modified: 2026-09-20T19:57:37.946Z
---

Amending the Speedy requirements corpus (`Q:\Work\Work\99 Documentation\speedy\requirements`) never edits live artifacts. Stage a full copy outside the vault, edit, validate, then publish ONLY into `review/amendments/<name>/` with `proposed/` copies, `README.md`, `Amendment.json`, `Validation.txt`, `Integrity.json`. Precedent: `shared-secrets-verification-r1`. Proposed copies carry `status: REVIEW`, keep their historical approvals, and each previously approved artifact adds exactly one "stale approval" warning — that delta is the expected signal, not a defect.

Three traps hit on 2026-09-20 while closing GAP-1 (installation protection key lifecycle) and GAP-2 (session-id size):

- **Pin propagation is a fixpoint, not one pass.** Changing one artifact changes its digest, which invalidates every `applies`/`prerequisite` pin naming it. Loop `digest` + rewrite pins until zero files change (~10 iterations for a 26-artifact closure), THEN `digest --write`. A new contract that applies a requirement of an artifact that applies it back makes the loop oscillate forever — that is a prerequisite cycle the validator would reject anyway. State the borrowed rule inline instead of linking back.
- **Codex runs as a second coordinator in this corpus and publishes batches without warning.** It appended to `ids.yaml` and rewrote ten artifacts mid-session. Record live file mtimes when staging, re-check before publishing, re-base drifted files, and never publish a live artifact another writer may hold.
- **`reqtools.py digest --write` rewrites the whole file through `dump_yaml`**, but the round-trip is stable, so a pin-only change still diffs to ~12 lines. Prose with `": "` inside a plain YAML scalar breaks the strict loader — rephrase rather than quote.

See [project_speedy_requirements_system](project_speedy_requirements_system.md) and [feedback_verify_no_guessing](feedback_verify_no_guessing.md).

**Applying an approved amendment (exec-004-negative-refusal-r1, 2026-09-22):**
- `reqtools.dump_yaml` defaults to a "Fictional example..." header. Live files have NO header, so always pass `header=""`.
- Validator: any approval not at the current revision on a READY artifact is an ERROR. Replace `approvals` with the one current approval, and append to `reviews` (history lives there).
- `yaml.safe_dump` emits anchors when one dict object is shared, e.g. the same `rev` in both a review and an approval. `load_strict` rejects them, so deepcopy each.
- Staged `proposed/` consumers go stale when another writer lands first (Codex landed 22:40, 10 minutes after my drift check). Rebase instead: take a fresh live copy, install only the approved normative file, then run a scoped pin fixpoint that rewrites only pins naming a digest this operation replaced. Guard the whole batch before the first write.
- Requirement-level pins (target `REQ-...`) are left as "impact review due" warnings, the same as the approved package did.
- The first `evidence/<ID>/<rev>/<VERIFY>.yaml` in the corpus is FEAT-STEP-COMMON-001's.
