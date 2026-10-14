---
name: reference_digest_receipts_stale_on_any_rebuild
description: "MyLoop receipts pinned to assembly digests go RED the moment any parallel code row rebuilds; re-certify at section close on a quiet machine, never mid-wave"
metadata: 
  node_type: memory
  type: reference
  originSessionId: 1a412ebb-924b-4fe0-a5a6-bf795960b18e
  modified: 2026-09-17T03:34:23.617Z
---

speedmerchants proof receipts (u9s-s0-4u U5, u9s-s0-8c Q5, u9s-s0-8d R5, u9s-s0-4p P4 ...) re-hash the DLLs the run used. Any parallel code row that changes source and builds (e.g. 52.S6.2 at 2026-09-16 03:11Z) makes them RED again within minutes, so a mid-wave re-certification row (52.S0.4za) closed green-at-collect and FAIL-at-verify with no defect of its own. Same for the whole-corpus self-test sweep receipt (u9s-s0-4x X2): ticket authors add self-tests continuously.

**How to apply:** do not dispatch receipt re-take rows while code rows build; certify digest receipts at section-close (section-close-full-tests) on a quiet machine; treat mid-wave digest REDs on regress lines as expected, not regressions. The u9s-s0-4x self-test takes ~261 s solo vs the sweep's 300 s timeout. Related: [[feedback_never_hold_ready_tickets]], [[feedback_section_close_requires_full_tests_incl_playwright]].
