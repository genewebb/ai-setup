---
name: reference-requirements-corpus-in-repo
description: Speedy requirements corpus lives in speedmerchants repo docs\requirements since 2026-09-28; vault copy retired/stale
metadata:
  node_type: memory
  type: reference
  originSessionId: e6692ca4-4cf5-4b6c-9bc6-113c26f431a3
  modified: 2026-10-12T17:42:39.253Z
---

Speedy requirements corpus = `{SpeedyRepo}\docs\requirements` (manifest.yaml `repositories` note: moved 2026-09-28). Vault copy `{VaultDocsRoot}\speedy\requirements` frozen 9/27, stale (ids.yaml/manifest.yaml differ). Stream builders amend repo files in commits.

- Validate: `python tools\requirements\reqtools.py validate docs\requirements` (Python 3.14, pyyaml 6.0.3, jsonschema 4.25.1, referencing 0.37.0 OK on CORPLTR94).
- Baseline 2026-10-12 @ f2e2719f: 313 errors / 162 warnings, all approval/pin drift (207 pinned-revision, 75 stale approval, 30 READY w/o current review/approval) + 1 digest mismatch FEAT-WVC-CANVAS-001 (G4.T137/T138 edits not re-digested). Gene chose: author on top, new work adds zero new errors.
- requirements-writing skill fixed 2026-10-12 to point at repo (was vault + Write-AIFile).
- Authoring worktree: `C:\devops\worktrees\speedmerchants\requirements`, branch `users/agenewe/requirements-authoring` off stream-sync.

**Laptop-to-SMVMTR1 workflow (Gene 2026-10-12):** author in the laptop worktree; Gene MANUALLY copies 1..N files into `D:\devops\repos\speedmerchants\docs\requirements` on SMVMTR1, then commits there with a pathspec-limited `git add -- <paths>` + `git commit -m ... -- <paths>` (keeps integrator's dirty src files out); integrator's next push carries it to origin. Why: SMVMTR1 integrator only pushes, never pulls, so a laptop push would make its pushes fail; laptop policy push=no anyway. Builders use HEAD worktrees, so uncommitted copies are invisible to them. At each hand-off give: NEW/MODIFIED file list, proof SMVMTR1's copy of each MODIFIED shared file (ids.yaml, manifest.yaml, generated\*) is unchanged since our base (else merge first), exact add/commit commands, validate vs 313 baseline. Fast-forward worktree to origin before starting.

Older memories naming the vault path ([[project-requirements-finish-tracker]]) predate the move.
