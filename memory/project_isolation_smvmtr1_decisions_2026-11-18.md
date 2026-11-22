---
name: project_isolation_smvmtr1_decisions_2026-11-18
description: "Gene 2026-11-18 isolation decisions on SMVMTR1 - step A first, unattended host changes incl. reboot allowed, TAI API open like UI, I bump 14.0.0 and commit TAI"
metadata:
  node_type: memory
  type: project
  originSessionId: 48e8ba62-42b2-44d2-b5a8-39d62dc558bf
  modified: 2026-11-18T09:00:55.464Z
---

Gene 2026-11-18 04:00 (AskUserQuestion answers, SMVMTR1 session):
- First step: **A** = read-only map of each VM's vCPU threads to host threads during slow vs normal SQL small-transaction passes.
- Unattended host changes: **all, including kernel cmdline/systemd changes and host reboot** (P4) with wait-and-reread. Still record every change in note 10/11 + page.
- New TAI API endpoints: **open like the UI** (no token, no loopback limit). Still no raw shell endpoint by my choice; mask saPassword/key paths in responses.
- Version: **I bump TAI to 14.0.0 and commit** TAI changes on `bug/isolation_testing_linux/genewebb`; Gene installs and pushes. git-guard may block speed-merchants; report, do not bypass.

New tasks same day: (1) API endpoints in TestAutoIsolation so I can drive all testing, (2) TAI updates for the full test set, (3) list of remaining work to automate everything without Gene.


Results 11/18 (TAI 14.0.0 API, committed 22d61186 + 62d89e23, not pushed): step A host vCPU sampling = host placement NOT the brake for the SQL small-transaction flip (slow state waits for host CPU less; same moves/CPUs; no busy core sharing at 1 s). KVM halt polling was off (halt_poll_ns_grow=0, 0 polls). Gene picked E: U10 grow=2 at runtime 05:14 = network round trips -29% (49-50 to 34-36 ms), commits -4%, flip unchanged. Guest IRQs static, irqbalance off. Gotcha: host sample id != job id (job result.sample). Work list: docs/isolation/Automation-Work-Left.md.

**Why:** Gene wants the isolation campaign (P3-P9) to run without his clicking.
**How to apply:** drive tests via the TAI API once installed; host changes OK without asking but log them. Related: [[project_isolation_test_plan_page_2026-11-17]], [[feedback_git_ok_testautoisolation_2026-11-18]], [[project_testautoisolation_2026-11-13]].
