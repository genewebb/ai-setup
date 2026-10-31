---
name: reference_royalts_web_connection_ie_engine
description: "Royal TS web connection opens in the legacy IE engine by default; modern web UIs (Proxmox) throw \"Script Error: Object doesn't support this action\" until the plugin is set to Chromium"
metadata:
  node_type: memory
  type: reference
  originSessionId: 70e0e446-378b-4cf7-8669-a34150c63598
  modified: 2026-10-27T14:57:45.748Z
---

Royal TS V7 web page connection (`RoyalWebConnection`) uses the global plugin, which on Gene's laptop is Internet Explorer. Proxmox web UI showed "Script Error ... Object doesn't support this action" (Line 1 Char 1).

Fix (Gene did it 2026-10-27): connection Properties > Advanced > Plugin > untick use global > Chromium. Also tick Ignore Certificate Errors for self-signed hosts.

Module properties: `UseGlobalPlugInWin` (bool), `PlugInWin` (plugin id, value NOT verified - set via GUI, do not guess), `IgnoreCertificateErrors` (bool). Related: [[project_home_lab_gmktec_evo_x1]].
