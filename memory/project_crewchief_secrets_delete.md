---
name: project_crewchief_secrets_delete
description: "CrewChief /secrets gained delete-section and delete-entry (2026-08-11) — decisions taken, why the last section is refused, and the two testability seams added"
metadata: 
  node_type: memory
  type: project
  originSessionId: 53e568ca-6ecd-4060-8b4d-c375fd5aadc8
  modified: 2026-08-11T14:05:16.767Z
---

Shipped 2026-08-11: delete an **entry** (trash button per row in `EditSectionDialog`, queued + undoable until Save, returned as `EditSectionResult.RemovedKeys`) and delete a **section** (Delete button per panel, confirm-then-apply) on CrewChief's `/secrets` console. Full unit suite green at 2937.

Decisions the user made when asked (do not re-litigate):
- **Last remaining section: BLOCK** with an explanation rather than deleting the store file or inventing a placeholder section. `SecretSchema.Validate` rejects an empty store, so the save could never succeed; the refusal happens *before* the confirm so the operator is never asked to approve something unsaveable.
- **No backup file.** Confirm dialog only — it names the entry count, warns that `{{$config:Section:Key}}` steps will fail, and says to Export first. Rejected both `secrets.json.bak` and timestamped copies.
- **No usage scan.** Generic warning text; the page does not pull in the step/workload stores to find out what breaks.

Two `protected virtual` seams were added to `SecretsManagement` because bUnit can drive neither Radzen's confirm nor a Radzen modal: `ConfirmAsync` (mirrors `Steps`/`Activity`) and `OpenSectionDialogAsync`. `EditSectionDialog.ProjectRemovedKeys` was extracted as a pure static so the delete-then-re-add filter is testable directly — Radzen fires `OnClose` only for a dialog it opened, so a bUnit-rendered dialog's `Close` is unobservable. That dead end cost a test-rewrite; don't try `DialogService.OnClose` again.

Also fixed while in there: a failed persist now rolls back the in-memory decrypted copy on **both** delete paths and on the edit path — previously a failed save left `_decrypted` holding changes that never reached disk.

Related: [[project_crewchief_secrets_shipped]] · [[project_crewchief_tier_rename]] · [[crewchief-secrets]] · [[project_crewchief_ui_conventions_2026-07]]
