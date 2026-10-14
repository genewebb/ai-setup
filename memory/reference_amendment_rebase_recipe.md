---
name: reference-amendment-rebase-recipe
description: "Tested recipe for rebasing a staged Speedy requirements amendment onto live (MP-9, 2026-09-26); scripts reusable from scratchpad mp9/ and B1's b1/"
metadata:
  node_type: memory
  type: reference
  originSessionId: 04ced72c-1138-47e1-95ba-71219b3cb09c
  modified: 2026-09-26T17:07:14.927Z
---

Rebasing an amendment package whose base amendment has since gone live:

1. Locate each base file by `old_file_sha256` from Amendment.json: hash every YAML under `review/amendments/**` (the old base usually sits in `<dep>/superseded-*/proposed/`).
2. `git merge-file --diff3` (ours = live, base = located base, theirs = package proposed). Resolve by rule, hashes masked: live==base -> theirs; theirs==base -> live; theirs = base + appended -> live + appended; author lists = live + this package's entries. Hand-resolve the rest (MP-9: 2 of 43).
3. Delta proof (base->theirs vs live->merged, hashes and status_reason masked) plus a per-item (REQ/AC/term/decision/row) "changed by both" check to find silently merged items to read by hand.
4. Propagation: reset merged files' declared revision to live's, map foreign hashes only where absent from the file's live text, then fixpoint. New files whose digest does not move drop out of moves.json; add them back by hand.
5. The glob over `Q:` SMB for foreign hashes takes >2 min; run it in the background.

Scripts: `%TEMP%\claude\C--devops-repos-speedmerchants\04ced72c-*\scratchpad\mp9\` (merge, resolve, deltacheck, propagate, status, checks, build, publish.ps1). Heredocs with many quotes broke Git Bash here; write long scripts with the Write tool. Related: [[reference_pin_fixpoint_regex_traps]], [[reference-reqtools-digest-write-reflows-file]].
