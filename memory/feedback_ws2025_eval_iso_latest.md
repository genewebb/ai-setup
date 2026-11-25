---
name: feedback_ws2025_eval_iso_latest
description: "Windows Server 2025 VMs: always use Gene's latest evaluation ISO in S:\\ISOs (newest *SERVER_EVAL* file)"
metadata:
  node_type: memory
  type: feedback
  originSessionId: 7986e46e-eb36-4bdb-a0ee-12f91e19b099
  modified: 2026-11-24T20:37:44.829Z
---

Windows Server 2025 VM builds use the latest evaluation ISO Gene downloaded to `S:\ISOs` (pick the newest `*SERVER_EVAL_x64FRE_en-us.iso`). As of 2026-11-24: `26100.32230.260111-0550.lt_release_svc_refresh_SERVER_EVAL_x64FRE_en-us.iso`, 8,152,356,864 bytes, SHA-256 7B052573BA7894C9924E3E87BA732CCD354D18CB75A883EFA9B900EA125BFD51; copied to CorpProxMox01 `/var/lib/vz/template/iso/`.

**Why:** Gene 2026-11-24 15:35: "Always use the latest Windows 2025 evaluation copy". No key; 180-day eval, activate online within 10 days.
**How to apply:** before building a Windows VM, list `S:\ISOs` and use the newest eval ISO; patch with Windows Update after install so the build matches the Profisee win25 container image. Related: [[project_isolation_decisions_2026-11-23]].
