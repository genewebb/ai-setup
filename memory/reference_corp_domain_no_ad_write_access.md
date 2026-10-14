---
name: reference_corp_domain_no_ad_write_access
description: No DC access and no AD write rights in corp.profisee.com — setspn/dsacls/sPNMappings/RBCD fixes are all off the table; propose host-side or app-side fixes
metadata: 
  node_type: memory
  type: reference
  originSessionId: 23c64c4d-7617-4cc7-8c1d-56566aee172f
  modified: 2026-08-05T14:06:53.617Z
---

Gene has **no DC access and no AD write rights** in `corp.profisee.com` (confirmed 2026-08-05).

- `setspn -S ...` on a computer object fails with `0x2098/8344 -> Insufficient access rights to perform the operation`.
- `dsacls` is not installed (no RSAT AD DS tools) on the lab boxes.
- DCs in play: CorpDC02, CorpDC03. Domain trust from member boxes is healthy (`nltest /sc_verify` clean) — the gap is authorization, not connectivity.

**How to apply:** never propose an AD-write remedy as the primary fix — SPN registration, computer-object
ACL repair (Validated write to SPN for SELF), domain `sPNMappings` edits, and resource-based constrained
delegation all require rights he does not have. Rank host-side (registry/WinRM/local policy) and
application-side (change the app so it stops needing the hop) fixes first, and list the AD change only as
"file a ticket with someone who has rights". Related: [[reference_corpsql03_missing_wsman_spn]].
