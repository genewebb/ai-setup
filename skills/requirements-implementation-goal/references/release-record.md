# Companion release or readiness record

Use the project's existing format or a readable table. This is handoff metadata, not a new normative artifact/schema or substitute approval. Do not allocate requirement IDs to it.

| Group | Contents |
|---|---|
| Identity | Area, release identifier, preparer/date, draft/issued state, full prompt locator |
| Authority | Standard, manifest, canonical form and tool versions/file hashes; actual source commit and dirty flag or accurately labelled uncommitted/unknown state |
| Selection | Root targets, normative contracts, decisions, transitive binding closure, exclusions and authority |
| Per artifact | ID, authoritative path, computed normative revision, actual status, review/approval locators, prerequisite pins |
| Snapshot | Retrievable immutable contents, file/bundle hashes and provenance; no duplicate active YAML IDs |
| Background | Required candidate/source/code references and inspection limits, labelled as context rather than additional obligations |
| Traceability | Complete REQ/AC/VERIFY index and reconciled counts; criteria remain in normative sources |
| Integration | Actual runtime dependencies and owners; unresolved boundaries in a draft |
| Execution | Repository/assigned checkout, baseline and existing edits, writable scope, resource/shared-file owners, task permissions and exclusions |
| Verification | Required methods, available environments, evidence destinations; planned and executed checks distinguished |
| Readiness | Validator result and its limits, manual gates, questions/answers pending, missing inputs or approval |
| Changes | Feedback route, impact review and explicit adoption of approved new revisions |

Keep known values in drafts and name missing required inputs. Never insert fake approvals or make a diagnostic snapshot appear issued. A historical approved baseline remains usable only with its actual contents and applicable disposition; a hash alone cannot reconstruct it. A superseded baseline or material discovered defect requires review of its use.

Before issue, compare the record to actual sources and snapshot readback. Ensure the prompt names this exact record. A new agent must be able to recover selection, identity and acceptance coverage without relying on a transient chat summary.
