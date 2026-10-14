---
name: project_worker_channel_adr_2026-09-25
description: "Gene chose 2026-09-25 - remote Speedy workers use mutual-TLS HTTPS long-poll to the coordinator, SQL internal to control, no RabbitMQ; ADR + tracker rows + WCH.1 mockups"
metadata:
  node_type: memory
  type: project
  originSessionId: 38d94a9d-5d56-4d42-a415-5cb6ec005991
  modified: 2026-09-26T01:22:46.253Z
---

Gene decided on 2026-09-25, after a RabbitMQ review. RabbitMQ is only an HTTP load target in the proofs today; it runs 0 connections and 0 queues, and SQL `dbo.WorkItem` is the live transport.

The decision: workers on other computers reach control through **mutual-TLS HTTPS, terminated by the coordinator, with the worker dialling out as a long-poll**. Only control holds SQL credentials. Lane A (workload steps and capability checks) comes first, then lane B (high-volume load work). **No broker.**

**Why:** FEAT-INSTALLER-001 (READY) worker-channel says a shared queue or SQL credential does not meet the contract. Today's installer writes a SQL connection string to every worker, which doesn't comply.

**Artifacts:**
- `requirements\decisions\ADR-WORKER-CHANNEL-001.yaml` (REVIEW).
- Requirements tracker rows WC1 (clean review), WC2 (Gene approves) and WC3 (lane-B feature).
- Coding tracker rows WCH.0-7; the code rows are blocked on the ADR.
- WCH.1 mockups: `speedy\ui\workers\`, artifact https://claude.ai/artifact/Pqrem2xLMJBqvw7yw9wsuX, awaiting Gene.

**How to apply:**
- Never propose RabbitMQ or direct SQL for remote workers.
- Easy gap to miss: remote journals must be uploaded over the channel (WCH.4), because the drain reads the shared `/journal` volume.
- The lane-A logic already exists in `src/Application/Hosts/` but no host composes it. `IWorkerChannel` has only test fakes.
- DPQ-12 (9 independent full stacks) means no current deployment needs remote workers yet.
