---
name: reference-rancher-desktop-autostart-is-login-scoped
description: Rancher Desktop autoStart fires at user LOGIN not boot, so Docker restart policies are moot after an unattended reboot - cost CORPVMHA1 8h03m of OTEL telemetry
metadata:
  type: reference
---

Rancher Desktop's `application.autoStart` + `application.startInBackground` (visible via
`rdctl list-settings`) mean **at user login**, NOT at boot. It is a user-session Electron
app driving WSL. No login = no dockerd = every container restart policy is inert.

A boot-time Scheduled Task is not a workaround: "run whether user is logged on or not"
runs in Session 0, where Electron will not start.

**Proven on CORPVMHA1, 2026-09-09 power outage** (Windows Server 2025, moby backend,
`otel/opentelemetry-collector-contrib:0.151.0`, `restart: unless-stopped` correctly set):

| Span | Duration |
| --- | --- |
| Last telemetry 00:39:38 -> boot 01:01:53 EDT | 22m (real outage) |
| Boot -> collector start 08:42:33 EDT | **7h 40m** (waiting for a login) |
| Total blackout | **8h 03m** |

Diagnostic that proves it in one shot: compare
`(Get-CimInstance Win32_OperatingSystem).LastBootUpTime` (local time) against
`docker inspect -f '{{.State.StartedAt}}'` (**UTC** - PowerShell prints it unconverted).

Fix = native Windows service, not autologon. Artifacts written to `C:\temp\otel-native\`:
ported config (every `0.0.0.0` -> `127.0.0.1`, since without port-publishing the bind
address IS the exposure), `Install-OtelCollectorService.ps1` (lifts env vars out of the
live container, `validate` before service creation, parity gate, rollback line), and
`CUTOVER.md`. Decommission gotcha: `docker stop` blocks `unless-stopped` but a later
`docker compose up` recreates and collides - retire the service in the compose file too.

Related: [[reference_docker_update_cannot_clear_limits]] · [[reference_rancher_desktop_switch]]
