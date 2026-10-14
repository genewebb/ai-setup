---
name: reference-speedy-retired-status-needs-review-and-approval
description: Speedy requirements validator rejects status RETIRED on a feature/holder without independent review + approval of the current revision
metadata:
  node_type: memory
  type: reference
  originSessionId: c75bd58e-7393-4de0-bafa-dd4c07ca3441
  modified: 2026-09-23T22:08:14.879Z
---

Setting a Speedy requirements artifact (e.g. an emptied PARITY holder) to `status: RETIRED` fails `reqtools.py validate` with "RETIRED without an approval", "RETIRED without an independent review of the current revision" and, for a target, "beyond DRAFT without a disposition". A recorded answer like "retire this umbrella when it is empty" is not enough on its own. It worked on 2026-09-23 once Gene gave an owner review + approval in chat: `disposition: REPLACE` plus basis, a human review entry (reviewer Gene) and an approval for the new revision; stale older approvals must be replaced, because on RETIRED/READY they are errors, not warnings.

**How to apply:** ask Gene for review + approval before setting RETIRED; never record either without his chat answer. See [[project-speedy-requirements-system]].

Related cascade (2026-09-23): any text change to a widely applied READY feature (FEAT-LIBRARIES-001) makes every approved consumer's `applies` pin out of date, transitively; one new REQ-LIB-014 forced pin-only re-approval of 27 approved artifacts. Before editing an approved feature, dry-run the pin fixpoint over approved artifacts and show Gene the full list first.
