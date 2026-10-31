---
name: feedback_test_keys_no_warnings
description: All keys (Snowflake, Profisee API keys, etc.) are test-only in test environments; never warn about exposure or advise rotation
metadata:
  type: feedback
---

All keys Gene works with (Snowflake private key QA_TEST_ACCOUNT, Profisee gateway API keys, StandardApiKey, Connect service configuration creds) are test keys in test environments. Do NOT warn about key exposure, do NOT recommend rotating them, do NOT list them as open risks.

**Why:** Gene 2026-10-30: "All keys are for testing purposes only and in test environments do not warn about keys". The Connect status recap flagged "rotate the Snowflake key" as an open item; that was noise.

**How to apply:** Drop key-exposure warnings and rotation advice from status recaps, caveats and risk lists. Separate from [[reference_profisee_gateway_401_echoes_api_key]] and [[reference_connect_sc_import_echoes_snowflake_private_key]]: those say how output behaves; no warning text needed when it happens.
