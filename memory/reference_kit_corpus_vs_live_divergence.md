---
name: reference_kit_corpus_vs_live_divergence
description: "Stream kit has TWO copies (corpus D:\\AIWork\\work-ai vs live link tree on the Azure share); publishing to corpus can clobber another session's pending, uninstalled corpus file"
metadata:
  node_type: memory
  type: reference
  originSessionId: 49da5f78-d98f-4cc2-a1dd-4c48eb8cd675
  modified: 2026-10-04T14:12:02.800Z
---

Stream kit files live in two places on SMVMTR1: the corpus `{AIWorkRoot}\skills\stream-kit` (where Publish-KitFile.ps1 writes) and the live link tree `{ClaudeHome}\skills\stream-kit` (a symlink to `\\smshareddrive...\AIWork\skills\stream-kit`, written by Install-AIMachine). An apply stops on drift, so work published to the corpus can sit uninstalled for hours while other sessions hand-edit the live tree.

On 2026-10-01 they diverged both ways: the corpus held coord's 2d56 (disk guard) and 5fcc (Revise note-only) work, waiting on `-AcceptDrift`; the live tree held a status session's Get-StreamStatus and Build-StatusPage edits. My Publish-KitFile of Test-StreamKitRecovery.ps1 (staged from live) overwrote coord's pending corpus copy, which held its case 55. I recovered it from that session's stage (`D:\tmp\streams\speedmerchants\kit-5fcc-root\stage`) with a git merge-file three-way merge.

**Why:** The skill's drift check compares the stage against LIVE only, and the corpus may hold a newer version that is not live yet.

**Guard since 2026-10-02:** `Publish-KitFile.ps1 -BaseHash <sha of the file you staged from | NEW>` refuses with DRIFT-REFUSED (exit 3) if the corpus copy has moved. Always pass it.

**How to apply:** Before Publish-KitFile, diff corpus vs live for every file you touch. When they differ, stage from the CORPUS and do a three-way merge (`git merge-file`, with the base taken from the other session's `kit-*-root\base`). Then run `Install-AIMachine.ps1 -WhatIf` to see the drift list. Merge every live-only edit into the corpus before `-AcceptDrift`, which needs the owner's OK. A session may still hand-edit live between your WhatIf and the apply (the status page files did at 20:30), so re-check live hashes right after the apply. Related: [[reference_kit_install_drift_check_then_copy_clobbers]].

**A held item can still be fixed twice (2026-10-04, kit item ad1f):** while this session held the item, another session published an equivalent fix to the corpus without taking it. Re-check corpus == live just before publishing each file, not only at stage time. When the corpus already holds an equivalent fix, keep it, drop your stage, and run both suites on a copy of the corpus before you install.
