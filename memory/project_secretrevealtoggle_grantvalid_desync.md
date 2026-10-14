---
name: secretrevealtoggle-grantvalid-desync
description: OPEN follow-up — SecretRevealToggle holds _grantValid per instance; sibling toggles sharing one host flag can render checked-but-disabled beside cleartext
metadata: 
  node_type: memory
  type: project
  originSessionId: 7dc6c870-9aa7-4891-a85e-d99e95480385
  modified: 2026-07-28T15:51:23.894Z
---

Open tracked item from the raw-JSON panes close-out review (2026-07-28), deliberately NOT fixed in that pass.

`SecretRevealToggle` caches `_grantValid` per component instance, refreshed only on its own `firstRender` or its own unlock/re-lock (`SecretRevealToggle.razor:115-141`). Now that sibling toggles share one host reveal flag (one flag per page since the consolidation wave), a toggle instantiated *before* the grant existed renders `checked` (host flag true) but `disabled` (its stale `_grantValid` false) with an **Unlock** button — while its card shows cleartext. Repro: no grant at load; expand two step cards; unlock via card 1 → card 2's switch is on-but-greyed and cannot re-lock without re-entering the master password.

**Why deferred:** cosmetic/confusing only — masking and the grant check on every flip are unaffected. The correct fix is a shared grant-state source (e.g. a scoped service the toggles subscribe to) rather than per-instance caching, which is broader than the JSON-panes feature.

**How to apply:** if touching SecretRevealToggle or adding another shared-flag page, fix the grant-state sharing first or the desync surface grows.

Related: [[crewchief-raw-json-panes]].
