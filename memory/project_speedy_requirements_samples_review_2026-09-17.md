---
name: project_speedy_requirements_samples_review_2026-09-17
description: 2026-09-17 independent review + fix of the Speedy requirements sample package; merged onto a Codex package that landed mid-task; reqtools.py is the validator/digest tool; canonical form is v2
metadata: 
  node_type: memory
  type: project
  originSessionId: 9acfe277-d355-4997-8acb-c29825f2acbe
  modified: 2026-09-18T01:27:49.554Z
---

**State after 2026-09-17 ~21:30.** `Q:\Work\Work\99 Documentation\speedy\requirements\` holds ONE merged package: RequirementDesign.md (13 edits: §3 `not_applicable`, §4 fictional marker, §5 metric state, §6 example in package spelling under DOMAIN `EXAMPLE-DUP`, §7 reference shape, §9 hash table, §12 validator, §14 fictional sample set, §15 layout incl. `templates/`, `RequirementDocumentExample/`, `review/`), `schemas/` (common + 9 per-type + inventory/id-registry/manifest/verification-results, draft 2020-12, `unevaluatedProperties: false`), `templates/` (13), `RequirementDocumentExample/` (12 YAML samples + 4 MD), `manifest.yaml`, `ids.yaml` (`document_kind: id_registry`), `existing/<app>/inventory.yaml` x5, `generated/BACKLOG.md`.

**Codex collision.** While I worked, Codex delivered its own "aligned authoring package" (20:36–20:45): 15 generated schemas, walkthrough samples, `review/` folder. I did NOT overwrite it blind: its 46 files are stashed byte-for-byte under `review/codex-package-2026-09-17/` (its `review/package-manifest.json` lists their hashes); its `review/FINAL-REVIEW.md`, `CHECK-RESULTS.md`, `check_package.py` stay in place. Kept from Codex: walkthrough file names, inventory shape, id-registry event fields, verification-results file. My findings + corrections are in `review/INDEPENDENT-REVIEW-2026-09-17.md` (14 findings, all applied).

**Tooling:** `C:\devops\repos\speedmerchants\tools\requirements\reqtools.py` — `digest [--write]`, `validate <root>`, `render`, `backlog`, `build-examples`. Python needs Windows paths, not `/q/...`. Validate on live root: 0 errors, 2 intended warnings (stale approval demo, draft REQ without AC), 1 intended note (consumer blocked through NFR). The PENDING/CONSUMER/DONOR variants are DERIVED from FEAT-EXAMPLE-001.yaml by `build-examples` — never hand-edit them. Canonical form is `speedy-canonical-v2` (excludes status, status_reason, superseded_by, authors, revision, reviews, approvals + 5 row progress fields).

**Skill** `requirements-writing`: linked (was in `$skills`, never linked), rewritten around the tooling + Write-VaultFile rule. Linker array: `myfable-foreman` -> `myloop`. `C:\Users\agenewe\AI\skills\synced` is Claude's own sync bucket, not a NATIVE user skill — leave it.

**RESOLVED 9/17 21:35 (Gene: "requirements process approved"):** process/standard/canonical v2/schemas/templates/tooling/sample package APPROVED as format+process; no sample gets an approval entry. Ambiguities fixed in standard §4/§9/§10 + validator: CAP completes READY on its own record; ADR `decision_status`<->`status` coupled (PROPOSED=DRAFT/REVIEW, ACCEPTED=READY, SUPERSEDED=SUPERSEDED+superseded_by, REJECTED=RETIRED+reason); status RETIRED/SUPERSEDED NEVER emits an ID `retire` event — only a record leaving the corpus (resolved Q-, archived artifact) does. `myfable-foreman` alias link deleted; drift = only `synced` (Claude's own bucket). Gene commits.

**Why:** the samples are what every live artifact is copied from; the parallel Codex package would otherwise have silently forked the field model.
**How to apply:** before authoring live Secrets artifacts, run `validate`; edit base sample then `build-examples`; see [[project_speedy_requirements_system]].
