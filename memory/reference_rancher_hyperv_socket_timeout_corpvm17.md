---
name: reference-rancher-hyperv-socket-timeout-corpvm17
description: "CORPVM17 docker FAIL 'failed to connect to the backend: timed out dialing Hyper-V socket' with rancher-desktop distro Running = hung WSL VM; fix rdctl shutdown + wsl --shutdown + rdctl start (worked 2026-10-14)"
metadata:
  node_type: memory
  type: reference
  originSessionId: f0454aab-598a-49d1-b5bc-df925330f846
  modified: 2026-10-14T23:52:52.135Z
---

Seen 2026-10-14 on CORPVM17 (stream host): Test-StreamHostReady `docker engine` FAIL; `docker version` client OK, server
`Error response from daemon: failed to connect to the backend: timed out dialing Hyper-V socket`; `wsl -l -v` showed
`rancher-desktop Running`, `rancher-desktop-data Stopped` (the data distro being Stopped is normal).

Fix that worked (engine came back as 29.5.3 within ~2 min):

```powershell
$rd = 'C:\Program Files\Rancher Desktop\resources\resources\win32\bin\rdctl.exe'
& $rd shutdown
wsl --shutdown
& $rd start
docker version --format '{{.Server.Version}}'
```

Second occurrence same day (19:46): a fast restart came up, then within ~1 min docker.log flooded with
`docker-proxy: error accepting client connection: ... bad file descriptor` and the timeout returned. Fixed by a SLOW
restart: `rdctl shutdown`, re-run `wsl -l -v` until BOTH distros show Stopped, then `wsl --shutdown`, `rdctl start`.
wsl-helper.log logs ~25 s of "timed out dialing Hyper-V socket" while the VM boots, then `Got WSL2 VM` + `Listening
npipe docker_engine`: those boot lines are normal, so check docker only after that line. Logs:
`%LOCALAPPDATA%\rancher-desktop\logs` (truncated on every Rancher start; never tail docker.log over SMB while it floods).

`docker --version` is client-only and proves nothing about the engine. If `wsl` itself errors with
HCS_E_HYPERV_NOT_INSTALLED instead, nested virtualization is off again: host-side fix in
[[project-stream-host-move-corpvm17-2026-10-13]].
