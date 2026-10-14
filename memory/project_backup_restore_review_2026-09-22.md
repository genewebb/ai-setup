---
name: project-backup-restore-review-2026-09-22
description: Backup/Restore release r1 verification 9/22 - Gene accepted a Claude review as the VERIFY-BAK verifier; F2 location warning built; F1/F5 back burner
metadata: 
  node_type: memory
  type: project
  originSessionId: 6acf0a47-dd63-41b3-be42-cc073d32347e
  modified: 2026-09-22T14:39:48.202Z
---

On 2026-09-22 Gene said to treat a fresh-context Claude review as the verifier for VERIFY-BAK-001/002/003 (crewchief-backup-restore-2026-09-21-r1). That overrides the FINAL-REVIEW rule that the verifier must be a different AI tool. It applies to THIS release only; do not assume it for other releases.

Review record: `C:\Users\genewe\Documents\Codex\2026-09-17\rea\outputs\claude-crewchief-backup-restore\independent-review-2026-09-22\Review.md`

Decisions:
- F1 (a forged manifest-listed unknown part is classed IntegrityFailure): back burner.
- F2: the preview warns when restoring the `backup-location` reference set repoints the folder. Built, uncommitted.
- F3 (listing matches archives by name only): OK as it is.
- F5 (unbounded decompression): back burner.
- F6 (cross-owner impacts): undecided.

REQ-UIDONE-003: Gene inspected and tested the Backup screen; "looks fine".

Round 2 (10:45): F4 FIXED at the shared store read path (dates stay text) plus a robust SeedGate date parse. F6: Gene said "kill an interrupted restore and let it start over, don't over engineer", so the restore journal and the template-install gate were DELETED; a failed unit puts its earlier definition back in-process and says "run the restore again". REQ-BAK-013/VERIFY-BAK-003 text now needs a staged amendment. The .loop gates b5 and u7b-15 were re-aimed.

Round 3 (11:16): `backup-location -> path` (AbsolutePath) is now a REQUIRED setup value in RequiredReferenceSets.ForThisBuild (EmptySetPermitted false). Nothing forces setup yet (the SetupCompletionService gate is not wired to any host); when forced first-run setup is built, it covers backup. The value may arrive by ANY route: the setup page, the Reference Data editor, a deployed template's reference defaults (the merge adds a missing key and never overwrites), or a restore of the References part (F2 warning). The check only asks whether a valid value is present.

**Why:** Gene owns the independence rule and can waive it.
**How to apply:** the remaining acceptance gap is REQ-TPL-010 (the welcome owner is NOT BUILT). Related: [[project-backup-screen-decisions-2026-09-22]]
