---
name: project_container_isolation_perf_2026-08-16
description: Measured container isolation between the two SQL 2022 containers — pinning halves interference and variance but does not isolate
metadata: 
  node_type: memory
  type: project
  originSessionId: c89b11b7-293e-4541-9e9d-95c030e9fe7c
  modified: 2026-08-16T16:19:57.261Z
---

Built `C:\devopslocal\repos\container-perf-iso` (standalone .NET 10 MSTest harness) and measured whether `sql2022-modelsource` and `sql2022-speedmerchants` interfere. Run 2026-08-16, 50 iterations per phase, 7 phases, both passes in one WSL2 VM boot (16 vCPU / 31 GB / swap 0).

**Findings:**
- Unlimited (as found — no cpuset, no memory limit): a saturated neighbour costs **+78% to +145%** median latency.
- Pinned (disjoint cpusets + 12 GB + `max server memory` 9216): **+44% to +56%**. Roughly halved, not eliminated.
- Pinning is FREE — solo baselines came out **4–11% faster** pinned (cache locality + no 2x memory over-commit).
- Run-to-run variance on a quiet machine: **13–24% unpinned, 8–16% pinned**. Directly relevant to the ~30% swing blamed on SaaS noisy neighbours — much of it reproduces on an idle laptop.
- Residual interference is memory bandwidth + shared vhdx disk. cpuset reaches neither. Tail is worst: one WriteBatch P99 hit 1194 ms against a 285 ms median.

**Three measurement traps found (each produced a wrong answer first):**
1. The first measured phase is systematically slow — dynamically expanding vhdx first-touch. Trusting a first baseline gave a **43% error**. Fix: burn-in + pool the bracketing solo phases.
2. A burn-in that hands straight into phase 1 creates a NEW artifact — the first phase is measured while the other container drains dirty pages. Fix: CHECKPOINT + settle between phases.
3. See [[reference_docker_update_cannot_clear_limits]] and [[reference_docker_memory_limit_lowering_oom]].

**Headroom matters:** a third pass at 7+7 vCPUs (only 2 spare instead of 4) was measurably WORSE — CoV nearly doubled (8.1%→13.6% AnalyticScan), drift went 0.4%→14.2%, 24/24 checks failed vs 21/24. Starving the VM kernel + Docker daemon costs more than the extra core gains. On a 16-vCPU VM keep 4 spare.

**End state:** containers left pinned at cpuset `0-5` / `6-11`, 12 GB each, `max server memory` 9216 MB — best-measured config.

Docs: `MyWorkVault\52 Technical\Containers\PeformanceTesting\` (00 Overview, 01 Environment Setup, 02 Test Method, 03 Results). Raw data under `container-perf-iso\results\`; only the `20260816-154616-unlimited` and `20260816-155518-pinned` folders are methodologically sound — earlier ones predate the corrections.
