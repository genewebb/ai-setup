---
name: reference_wsl_shutdown_wedges_docker_desktop
description: "wsl --shutdown leaves Docker Desktop stuck in \"stopping\" with 500 errors — needs an explicit docker desktop stop then start"
metadata: 
  node_type: memory
  type: reference
  originSessionId: c89b11b7-293e-4541-9e9d-95c030e9fe7c
  modified: 2026-08-16T16:09:39.529Z
---

Docker Desktop does not recover on its own from having its WSL distro pulled out from under it. Observed 2026-08-16, Docker Desktop 4.86 on CORPLTR94.

After `wsl --shutdown`:
- `wsl -l -v` shows `docker-desktop` as **Stopped** and it never restarts
- `docker desktop status` reports `stopping` indefinitely
- `docker desktop start` replies "Docker Desktop is already running" and does nothing
- every engine call returns `request returned 500 Internal Server Error for API route and version http://%2F%2F.%2Fpipe%2FdockerDesktopLinuxEngine/v1.55/info`

Waiting does not clear it — polling `docker info` just burns the timeout.

**Fix:**

```powershell
docker desktop stop
docker desktop start
```

`docker desktop stop` exits 1 with "Could not retrieve status" — that is expected here, not a failure. The subsequent `start` succeeds. Containers return afterwards under their restart policy.

**How to apply:** any script that runs `wsl --shutdown` (e.g. to apply `.wslconfig`) must follow it with that explicit stop/start cycle rather than waiting for auto-recovery. Wired into `C:\devopslocal\repos\container-perf-iso\scripts\Invoke-IsolationExperiment.ps1`.

Related: [[reference_docker_aspire_class_setup]], [[project_container_isolation_perf_2026-08-16]].
