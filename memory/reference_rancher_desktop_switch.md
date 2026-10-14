---
name: reference-rancher-desktop-switch
description: Dev box moving from Docker Desktop to Rancher Desktop on the dockerd/moby engine; prior Docker Desktop gotchas are unverified there
metadata: 
  node_type: memory
  type: reference
  originSessionId: 8e3b2f34-cb8e-4f46-999a-5cb099150143
  modified: 2026-08-31T01:04:45.177Z
---

Gene is replacing Docker Desktop with **Rancher Desktop** on the dev box, decided 2026-08-30
(speed-merchants vNext D21). **Engine must be dockerd (moby), not containerd.**

**Why the engine matters:** the speedmerchants repo makes 93 `docker` invocations across 17 files —
73 `docker compose`, 10 `docker kill`, 5 `docker ps`, 4 `docker run`, 1 `docker inspect` — including
every `.loop\criteria\k*.ps1` wrapper. dockerd/moby is drop-in and all of them keep working.
containerd has no `docker` CLI (it is `nerdctl`) and would mean rewriting all of them AND re-earning
every kill-proof measurement taken so far, since a runtime change re-baselines the numbers.

**Artifacts on disk (2026-08-30, pre-switch):**
- Runbook: `Q:\Work\Work\52 Technical\Containers\Rancher\FINAL-Rancher-Migration-Runbook_2026-08-30.md`
  (project-specific before/after). Generic mechanics: `Switch-Docker-Desktop-to-Rancher-Desktop-Windows-11.md`
  in the same folder — follow that one, NOT the 2026-08-19 doc, whose ordering forfeits the rollback.
- `C:\DockerMigration\` — baseline captures, both volume archives, and `BEFORE-numbers.md` (the
  single comparison file for the post-migration acceptance test).

**Docker Desktop baseline being replaced:** client/server 29.7.2, Compose v5.3.1, overlayfs,
**cgroup v1**, kernel 5.15 WSL2.

**The cgroup finding — check this after switching:** R17's spec (vNext master §9) has the agent read
`/sys/fs/cgroup` `cpu.max` / `memory.max` / `cpuset.cpus.effective` — **cgroup v2** filenames that do
not exist on v1. R17 is unimplemented (UoW-7), so nothing is broken, but the spec was written against
v2 while Docker Desktop presented v1. Rancher likely gives v2, which would quietly fix the mismatch.
Verify and pin the R17 implementation to whatever Rancher actually presents.

**How to apply:**
- Nothing needed migrating: both named volumes are throwaway proof data (schema comes from the three
  migrators, evidence of record is committed in `VERDICT.md`/`SCORECARD.md`), and every image
  rebuilds from source. See [[project_vnext_due_diligence_2026-08-28]].
- The proof suite IS the migration acceptance test — re-run the chaos/redelivery/dial proofs on the
  new runtime. A proof that fails there and passed on Docker Desktop is a finding, never a script to
  loosen.
- **Treat these as unverified on Rancher until re-observed** — all three were Docker Desktop
  observations: [[reference_docker_memory_limit_lowering_oom]],
  [[reference_docker_update_cannot_clear_limits]], [[reference_wsl_shutdown_wedges_docker_desktop]].
- The insecure-registry setting for a self-hosted `registry:2` lives inside the WSL VM under Rancher,
  not in a desktop dialog — confirm the path on the box rather than assuming `/etc/docker/daemon.json`.

---

## SHIPPED + ACCEPTED 2026-08-30. Migration done, Docker Desktop uninstalled, box rebooted 16:34.

Full proof suite re-run on Rancher/dockerd: **5 of 5 PASS** (zero-loss chaos 500/500, SQL lease
redelivery, SQL per-item visibility, dial latency 1.327s fleet response, K2/K3/K4). **Rancher caused
zero failures.** Suite at close 969 unit + 8 architecture, 0 failures.

**Post-reboot verification (16:47–16:53), all green:** `docker` resolves only to Rancher's
`...\win32\bin\docker.exe`; no `Docker\Docker` on machine or user PATH; client `29.6.2-rd` / server
`29.5.3`; dead `desktop-linux` + `desktop-windows` contexts REMOVED; `docker info` = 29.5.3 /
"Rancher Desktop WSL Distribution" / Cgroup Version 1; `hello-world` runs; all three
`speedmerchants-*` images intact at ~372MB with correct entrypoints. Smoke test (dotnet test + chaos)
NOT run — left as the open step in AfterBoot.md.

**Runs under `corp\genewe`, driven from `corp\agenewe` — this is correct, not a misconfiguration.**
State lives in `C:\Users\genewe\AppData\Local\rancher-desktop`; the engine pipe is machine-global.
Full reasoning in [[reference_corp_dual_accounts]].

## cgroup: v1 → v2, and the WSL kernel is why (RESOLVED 2026-08-30 20:57)

The full sequence, because each step corrected the one before and the final rule is what matters:

1. **Predicted** Rancher would present cgroup v2. **Wrong.**
2. **Observed** Rancher presenting **v1**, same as Docker Desktop, on kernel `5.15.167.4-1` — because
   the **WSL kernel owns that answer, not the container runtime**. Both are WSL2 distros.
3. **Upgraded WSL** `2.4.11.0` → **`2.7.12.0`** at the UoW-6-close boundary, which took the kernel
   `5.15.167.4-1` → **`6.18.33.2-2`** — and cgroup flipped to **v2**.

**Measured after, in a container:** `CGROUP: v2`, controllers `cpuset cpu io memory hugetlb pids rdma`;
all three files R17's spec reads now exist (`cpu.max`, `memory.max`, `cpuset.cpus.effective`) where
they were absent an hour earlier. `docker info` reports `Cgroup Version: 2` and the four **blkio
throttle warnings are gone — per-container disk I/O limits work again**, which they did not on v1. One
new warning takes their place: `No swap limit support`.

**THE DURABLE RULE, now proven rather than argued: R17 must DETECT the cgroup version, never assume
it.** This same machine presented v1 and v2 on the same afternoon with no code change between — only a
kernel upgrade. Anything that hard-codes v1 or v2 filenames is one `wsl --update` from being wrong.

**Every measurement taken before 2026-08-30 20:55 is on a different substrate** — the 1.327 s dial
latency, the throughput figures, the kill-proof timings. Comparing UoW-7's numbers against them is
comparing across kernels; re-baseline rather than assume continuity.

Engine and the `~/.docker` repair both survived the upgrade untouched: client `29.6.2-rd`, server
`29.5.3`, `docker compose` v5.3.1.

## `~/.docker` cleanup — FOUND AND FIXED 2026-08-30 19:25. No workaround needed any more.

The Rancher install leaves the **user's** `~/.docker` still pointing at uninstalled Docker Desktop.
Bare `docker` worked (it is on PATH from Rancher), so this hid behind a green smoke test:
**`docker ps` succeeding is not evidence that `docker compose` does** — the post-reboot check ran
`hello-world`, which needs no plugin. Three separate leftovers, all now fixed:

1. **`~/.docker/cli-plugins` held only dead symlinks** to `C:\Program Files\Docker\Docker\...`
   (`docker-dev`, `docker-feedback`, `docker-sbom`), and Rancher's compose/buildx were never linked
   there — so `docker compose <anything>` failed while `docker ps` worked. That breaks every script in
   speedmerchants that shells out to compose (73 of its 93 docker invocations). **Fixed:** dead links
   removed; `docker-compose.exe` and `docker-buildx.exe` **symlinked** (not copied, so a Rancher
   upgrade carries through) to the real location — note it is **`...\win32\docker-cli-plugins\`, NOT
   `...\win32\bin\`**, which is why searching `bin` finds nothing.
2. **`config.json` had `"credsStore": "desktop"`** — naming `docker-credential-desktop.exe`, which was
   uninstalled with Docker Desktop. Any registry login would fail. **Fixed:** set to `wincred`;
   Rancher ships `docker-credential-wincred.exe` in its `bin`.
3. **`config.json` carried Docker Desktop `plugins` + `features` hook blocks** (ai/compose/debug
   hooks). **Fixed:** removed. Backup at `~/.docker/config.json.bak-2026-08-30`.

Verified with `DOCKER_CONFIG` unset: `docker compose version` → v5.3.1, `docker buildx version` →
v0.35.0, `docker info` plugin list shows both, and `docker compose config --services` parses the
speedmerchants compose.yaml (exit 0). The old `C:\tmp\dockercfg` workaround directory is now
redundant.

**`docker info` warns "No blkio throttle.read_bps_device support"** (and the write/iops variants) —
a **cgroup v1 consequence**, not a Rancher fault. It means per-container **disk I/O limits are
unavailable on this box**, which R17's isolation acceptance needs to know: CPU and memory limits work,
disk throttling does not. Re-check after the deferred WSL upgrade.

**Leftovers still on disk:** `docker-desktop` WSL distro still registered to agenewe, backed by
`C:\devopslocal\Containers\DockerDesktopWSL\main` (and `C:\devopslocal` is itself stale — moved to
`D:`). Plus `C:\DockerMigration\`. Keep both until Rancher has days of use behind it, then clean up.

**Post-reboot record:** the Rancher folder's `AfterBoot.md` in the work vault, updated 16:55 with the
verification table, account topology, WSL deferral, and a new Owed item 7 (bare `speedmerchants-cli`
prints its banner then exits 1, matching its own exit-code table — the runbook's "exit 0" expectation
is the wrong side).
