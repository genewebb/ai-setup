---
name: reference-connect-sc-import-echoes-snowflake-private-key
description: Connect service configuration import response echoes the Snowflake PRIVATE KEY unmasked; CrewChief ConnEx step prints it into run output
metadata:
  node_type: memory
  type: reference
  originSessionId: 91871b75-b25a-4910-820d-badb705fb365
  modified: 2026-10-15T17:15:02.837Z
---

A Connect `Import ServiceConfiguration` response masks passwords and tokens (`4Vv***GDV`, `dap***8-3`) but returns the Snowflake `PrivateKeyVault` value (the full PEM) in clear text. CrewChief's ConnEx step prints the response body into the run output, about 3,700 characters, so most of the key is shown. Seen 10/15/2026 on SMVMTR1 (`connect-service-configurations-create`, Snowflake, user QA_TEST_ACCOUNT).

It was not in the CrewChief log files (`web\logs`); it is in the UI run output and in anything Gene pastes.

**How to apply:** Never ask for or paste connect-setup or service-configuration run output whole; ask only for the failing step line. A CrewChief fix (mask PEM blocks or skip response bodies on ConnEx imports) is still open. Related: [[reference-profisee-gateway-401-echoes-api-key]].
