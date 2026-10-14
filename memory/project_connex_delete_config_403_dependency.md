---
name: project_connex_delete_config_403_dependency
description: ConnEx returns 403 when deleting a ServiceConfiguration still referenced by a Strategy; delete strategy first
metadata: 
  node_type: memory
  type: project
  originSessionId: 8b8867b7-b89d-47cf-a33b-b7e810f45b44
---

In Connect export test workflows, deleting a ConnEx **ServiceConfiguration** while an IntegrationStrategy still references it → ConnEx **HTTP 403 Forbidden** (seen in exec 10000171, "Delete ConnectExport Service Configuration" step).

**Why:** ConnEx forbids removing a config that's in use by a strategy.

**How to apply:** Order the teardown so the **strategy delete runs before** the service-config delete. Reordering the "Delete … Strategy" step to the top fixed the 403 (exec 10000172: deletes+create then succeeded). This is a step-ordering/dependency issue, not auth. Distinct from the follow-on bodyless-500 on strategy import — see [[reference_connex_service_store_and_logs]].
