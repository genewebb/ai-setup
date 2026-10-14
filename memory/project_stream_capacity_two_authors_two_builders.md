---
name: project-stream-capacity-two-authors-two-builders
description: Stream session caps by host - laptop was 2 authors + 2 builders (RAM); SMVMTR1 (32 cores/256 GB) runs everything, token budget is the ceiling
metadata:
  node_type: memory
  type: project
  originSessionId: 65137446-4524-4f40-bffb-1a4ca1b48277
  modified: 2026-09-29T03:02:27.519Z
---

**Laptop (CORPLTR94), until 9/28:** at most 2 stream-author and 2 stream-build sessions, plus integrator, status and
coordinator. Host RAM and CPU could not carry more, because both Profisee installs share the box; see
[[project-local-two-profisee-installs-required]].

**SMVMTR1, from 9/28 23:00:** Gene runs the whole kit on SMVMTR1 alone (32 cores, 256 GB). SMVMTR2 is not a build host
for now. Opening more author and builder sessions is his lever there. The ceilings are the Claude token budget, the
single integrator, ready work (ticketed tasks), and graders that need the compose stack or port 5310, which run one at a time.

**How to apply:** on SMVMTR1, "add a builder" is a valid lever only when the status page shows ticketed tasks
waiting and the integrator is keeping up. Never propose it on the laptop. Related: [[project_stream_host_smvmtr1_2026-09-28]].
