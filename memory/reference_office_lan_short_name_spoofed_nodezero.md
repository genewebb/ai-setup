---
name: reference_office_lan_short_name_spoofed_nodezero
description: "On office LAN, short host names (CORPNAS01, SMVMTR1) resolve to 10.36.53.187 = nodezero.corp.profisee.com (pentest poisoner); SMB gives \"Invalid Signature\". Use FQDNs."
metadata:
  node_type: memory
  type: reference
  originSessionId: e6f37816-fa49-4733-9584-3c9c44eacec9
  modified: 2026-11-16T13:28:40.873Z
---

2026-11-16: dpall -Package warnings "Share not reachable \\CORPNAS01..." and "Invalid Signature" on \\SMVMTR1\C$ in office only (fine at home).
Cause: short names answered with 10.36.53.187 (reverse = nodezero.corp.profisee.com, Horizon3 NodeZero style LLMNR/NBT-NS poisoning). FQDNs resolve right (SMVMTR1 10.0.0.6, CORPNAS01 10.36.55.17).
Fix applied: C:\Deploy\Setup\ProfileMachineConfig.md PackageShare + SharedBitsHost set to *.corp.profisee.com. Verified Test-Path both shares + Invoke-Command SMVMTR1 FQDN OK.
**How to apply:** any UNC/remoting to corp boxes from laptop in office = use FQDN. Related [[reference_shared_bits_smvmtr1_azure_relay]].
