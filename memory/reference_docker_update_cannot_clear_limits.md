---
name: reference_docker_update_cannot_clear_limits
description: docker update exits 0 and changes nothing when asked to clear a cpuset or memory limit — silent-failure trap
metadata: 
  node_type: memory
  type: reference
  originSessionId: c89b11b7-293e-4541-9e9d-95c030e9fe7c
  modified: 2026-08-16T16:09:10.261Z
---

`docker update` CANNOT clear a resource limit. Verified 2026-08-16, Docker Desktop 4.86 / engine 29.7.2, WSL2 backend, cgroup v1:

```powershell
docker update --cpuset-cpus="" <container>        # exit 0, cpuset UNCHANGED
docker update --memory 0 --memory-swap 0 <c>      # exit 0, memory UNCHANGED
```

Both print the container name and exit **0** while doing nothing. Docker reads an empty string or zero as "no change requested", not "remove the limit". Only recreating the container truly clears one.

Consequence: any script that checks `$LASTEXITCODE` reports success and leaves the container on stale limits. A perf baseline taken afterwards measures the wrong configuration with no error anywhere.

**How to apply:** never trust the exit code of `docker update` — re-read `docker inspect --format '{{.HostConfig.CpusetCpus}}'` / `'{{.HostConfig.Memory}}'` and compare against what was requested. To "un-pin" without recreating, WIDEN instead of clear (`--cpuset-cpus 0-15 --memory 28g`).

See [[reference_docker_memory_limit_lowering_oom]] for the ordering hazard when tightening, and [[project_container_isolation_perf_2026-08-16]] for the experiment this surfaced in.
