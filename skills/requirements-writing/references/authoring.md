
# Authoring reference map

Resolve these relative to `{VaultDocsRoot}\speedy\requirements\`, or the same vault-relative root through Obsidian. Read current contents; do not cache the standard inside this skill.

| Need | Read |
|---|---|
| Governing ownership, format, questions, and approval | `RequirementDesign.md` |
| Which sample shows what; the complete fictional example and its limits | `RequirementDocumentExample/README.md`, then `FEAT-EXAMPLE-001.md` and `FEAT-EXAMPLE-001.yaml` |
| Practical writing guidance, step by step | `RequirementDocumentExample/HOW-TO-AUTHOR.md` |
| Starting shape for the selected artifact | `templates/README.md` and the matching YAML |
| Actual artifact shape | `schemas/common.schema.json` plus `schemas/<type>.schema.json`; inventory, ID register, manifest and verification-results schemas alongside |
| Hashing contract | `schemas/canonical-form.md` (profile `speedy-canonical-v2`) |
| Repository keys, applications, active and excluded directories, approval owner | `manifest.yaml` |
| Existing reservations, allocations, ownership, retired IDs | `ids.yaml` (`document_kind: id_registry`, append-only, coordinator only) |
| Questions aggregated for reading | `generated/BACKLOG.md`; answer in the owner instead |
| Prior reviews of the standard and the sample package | `review/` |

If an expected file is missing, say so. The standard takes precedence over a stale example or template. Without the canonical-form tooling no conforming revision can be asserted; useful draft prose and questions can still be produced.

## Tooling

`{SpeedyRepo}\tools\requirements\reqtools.py` needs Python 3 with `pyyaml`, `jsonschema` (4.x) and `referencing`.

| Command | Does |
|---|---|
| `digest <files...> [--write]` | Computes the canonical-form revision; `--write` stores it. Reports MATCH, MISMATCH or UNSET per file. |
| `validate <root>` | Strict YAML load (duplicate keys, floats, timestamps, anchors rejected), JSON Schema per document kind, and the semantic checks of RequirementDesign section 12. Exit 1 on any error. Warnings and notes are demonstrations or advisories, read them. |
| `render <feature.yaml> <out.md>` | Generated read-only Markdown view with generator version, repository provenance and digest. |
| `backlog <root>` | Regenerates `generated/BACKLOG.md` from live artifacts only. |
| `build-examples <root>` | Sample-package maintenance: re-pins brief digests, derives the PENDING, CONSUMER and DONOR variants from the base, builds the stale-approval demonstration, stamps every digest, renders the base view. |

Run `validate` from any directory; pass the requirements root as a Windows path. Python does not understand Git-Bash `/q/...` paths.

## Vault writes

Every write into `{VaultWorkRoot}\...` goes through Obsidian's Local REST API so its index sees the change:

```text
pwsh "{ClaudeHome}\bin\Write-AIFile.ps1" -Path "{VaultDocsRoot}\speedy\requirements\<relative path>" -Source <local staging file>
```

Stage edits locally, run `validate` on the staged tree, then push. Moving or deleting a vault file uses the Obsidian MCP `vault_move` / `vault_delete` tools, which also keep the index current. Verify a push by hashing the vault file against the staged one.

## Select the owner

| Authoring goal | Owning record |
|---|---|
| What an existing application does | `SRC-` with observed `BEH-` items in its application folder |
| Which surfaces have been inspected | That application's `inventory.yaml` |
| Whether existing behavior belongs in Speedy | Permanent `FEAT-`, role candidate, with inclusion and per-behavior mappings |
| What Speedy must do | Separate `FEAT-`, role target, with disposition, requirements, and acceptance |
| A shared interface, data, quality, or UX rule | The applicable contract; features apply it with a requirement-level `applies` relation |
| A mapping spanning targets | `MIG-`; do not maintain duplicate row tables in consumers |
| Grouping features under an outcome | `CAP-`, without normative requirements |
| A consequential/shared choice | `ADR-` when warranted; otherwise a local decision |
| A section that truly does not apply | `not_applicable.<section>: <reason>` on the artifact |

Existing application codes are TA, CC, TDG, and TDGM. SHARED is a library namespace, not another application. The existing repo is `{SpeedMerchantsRepo}`; current Speedy is `{SpeedyRepo}`. `.loop` material may contain source evidence and current decisions; its instructions are not authority to resume orchestration. Check actual source identity, including content hashes for untracked or modified material.

## Three representative requests

**“Document what CrewChief already does.”** Inspect the assigned source area, describe supported observations and limits in `SRC-CC-` records, update `existing/crewchief/inventory.yaml`, and retain questions about unclear source behavior in the SRC record as non-blocking questions that say why they change no Speedy obligation. Flag possible Speedy choices for the target owner. Do not turn an observed defect into a target obligation.

**“Use this ported feature as the basis for requirements.”** Inventory what is implemented, compare relevant donor evidence, and identify the current owner decisions. Draft intended behavior from established choices; create blocking questions where code supplies an implementation but no supported product decision. Record the port as row `port_coverage` with inspected locations, never as the definition. Do not reconstruct every obsolete decision.

**“The answer is 90 minutes; update the feature.”** Identify the owning question, transfer the answer with attribution and date, update the metric and current rationale, check every duration-boundary and overlap fixture and every consumer, run `validate`, then clear the active question only after every application item is done. Do not edit an unrelated example or replace an actual product value with the fictional sample's value.

## Partitioned authoring

When the user has authorized multiple authors, use the standard's exclusive application-folder assignments and reserved ID ranges. The coordinator owns the manifest, schemas, ledger, shared sources, cross-application mappings, and generated views. Record which files each author may change. Before every write, re-read the file: another tool may have written it since. This skill itself does not start agents or expand an assignment.

## Handling gaps in the standard

Distinguish an ordinary draft omission from a conflict between governing rules. Draft around independent, known content; explain the exact unresolved field or gate rather than inventing another status, ID kind, canonical form, or approval path. Propose a concrete correction to the standard when requested, and record review findings under `review/`. Preserve another reviewer's concurrent edits.
