---
name: project-requirements-moved-into-repo-2026-09-28
description: As of 2026-09-28 the Speedy requirements corpus lives in the repo at D:\devops\repos\speedmerchants\docs\requirements, not the Q: vault
metadata:
  type: project
---

On 2026-09-28 Gene moved the Speedy requirements corpus into the repo. The live root is
`D:\devops\repos\speedmerchants\docs\requirements\` (same layout: features/, interfaces/, data/, schemas/,
generated/, decisions/, quality/, reviews/, templates/, ids.yaml, manifest.yaml). The old vault root
`Q:\Work\Work\99 Documentation\speedy\requirements\` is stale, and ticket `.streams\tickets\G4.T003.md`
had already recorded it as unreachable from the stream host (SynologyDS918 not reachable).

Corrected that day: `.streams\tasks.json` `requirements[]` (under the tasks.json lock), 4 `.streams\plans\`
files, 21 `.streams\tickets\` files, plus `stream-plan/SKILL.md` and `stream-kit/stream-howto.md`.

The vault copy IS retired (coordinator item IN-20260929001947-e99b: 645 files, commit ee254cd, identical to the
vault, and the stream hosts cannot reach Q:). On 2026-09-28 the `requirements-writing` and
`requirements-implementation-goal` skills were repointed to the repo and their Obsidian Local REST API /
`Write-VaultFile.ps1` write protocol was removed: a requirement edit is now an ordinary file write in the repo.
Inside `.streams` the paths are REPO-RELATIVE (`docs/requirements/<area>/<file>`); only `tasks.json`
`requirements[]` keeps the absolute root, because it must resolve from any working directory.

On 2026-09-29 `pyyaml`, `jsonschema` and `referencing` were installed into C:\Python314 so
`reqtools.py validate <root>` runs here: 0 errors, 164 warnings over 254 artifacts. `manifest.yaml`
`repositories.requirements.root` was repointed from the vault to the in-repo root, which is what made the
corpus's own locators verifiable at all. The corpus arrived as CRLF and was renormalised to LF the same day
(`.gitattributes`: `docs/requirements/** text eol=lf`, 645 files, left uncommitted), because its citations
hash the LF bytes. Two findings are in `.streams/owner/questions.md`: three ADR-WVC-SCENARIO-MODEL-001 pins
are real content drift, and five data citations record the CRLF hash and need a re-hash, not an edit.

Related: [[project_stream_kit_replaces_myloop]], [[project_speedy_requirements_system]],
[[reference_obsidian_smb_vault_watcher_blind]].
