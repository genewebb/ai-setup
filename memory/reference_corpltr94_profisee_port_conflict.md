---
name: reference-corpltr94-profisee-port-conflict
description: "On CORPLTR94 the running Profisee 26.1.0 (speedmerchants) service holds port 8003, so a co-installed 26.2.0 instance must use a different maestroServicePort"
metadata: 
  node_type: memory
  type: reference
  originSessionId: 12c5e146-c909-4a33-a49f-6cce5ea7b60f
  modified: 2026-07-31T01:10:13.567Z
---

`CORPLTR94` runs **two** Profisee instances side by side. `Profisee 26.1.0 (speedmerchants)` is RUNNING
and **LISTENING on TCP 8003** (verified via `netstat -ano` + `sc queryex` PID match). The shipped
`configuration-values:maestroServicePort` default is also **8003**, so a Configure of a second instance
creates its service and then cannot start it — the port is already bound.

**Why:** the failure is near-silent. `Configuration.exe` **always exits 0**
([[reference_configuration_exe_failure_modes]]), so the Configure step can report **Succeeded** while
leaving the new `Profisee 26.2.0 (Profisee)` service **STOPPED**. The only reliable signal is querying the
service state directly, not the step badge.

**How to apply:** put the machine-specific port in **reference data, not the workload**.
`reference-kv\configuration-values.json` is per-CrewChief-installation, which is the correct layer for a
fact about one box — the workload keeps its portable `{{$ref:configuration-values:maestroServicePort}}`
indirection and other machines keep their own value. Set this box to a free port (8004–8008 were all free
2026-07-30; **8006** chosen). Note every workload on this box shares that reference set, which is desired
here since 8003 is permanently taken.

No other Configure switch collides: `maestroWebAppName` / `maestroAppPoolName` are `Profisee` while the
26.1.0 instance is `speedmerchants` — different app + app pool under the same `Default Web Site`.

Do not stop or reconfigure the 26.1.0 service — it is deliberately kept running on this box.

Related: [[project_crewchief_reference_pickers]] · [[reference_configuration_exe_failure_modes]]
