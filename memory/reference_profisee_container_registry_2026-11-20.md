---
name: reference_profisee_container_registry_2026-11-20
description: "Profisee container registry profisee.azurecr.io - Gene's token is pull-only (no catalog/tag list); profiseeplatform 2022r1.0/2022r2.0/2023r1.0 are Windows Server 2019 images; current tags unknown"
metadata:
  node_type: memory
  type: reference
  originSessionId: 7986e46e-eb36-4bdb-a0ee-12f91e19b099
  modified: 2026-11-20T20:41:33.153Z
---

Credentials: `C:\Deploy\Secrets\containers.txt` (username, password, docker login line). Never print the password;
read it inside a script (`D:\tmp\...\scratchpad\acr_list.py` pattern: basic auth to `/oauth2/token`, then Bearer).

**Updated credentials (2026-11-20 15:45): `C:\Deploy\Secrets\containers_updated.txt`** (format: ```User / ```Password /
docker login line; parse the docker login line). This token CAN list the catalog and tags. 8 repos: dev/modeling,
keyvaultalpine, profisee-debug, profisee2020r1, profisee2020r2, profiseebase, profiseeplatform (releases),
profiseeplatformdev (dev builds). Tag format `YYYYrN.0[-build][-p]-win22|-win25`. All Windows images, no Linux one.
2026: dev repo has r1 (win22 only), r2, r3, r4 (built 2026-11-20); release repo has 2026r1-r3 (no r4 yet). `-win25`
= 10.0.26100 = Windows Server 2025 (process isolation on a WS2025 host); `-win22` = 10.0.20348. Script:
`acr_list.py` in the session scratchpad (Bearer token with `pull,metadata_read`).

Facts checked 2026-11-20 15:15 (old pull-only token):
- Registry `profisee.azurecr.io`. Token grants `pull` on any repository name, but no `registry:catalog:*` and no
  `metadata_read`, so `_catalog` and `tags/list` return 401. Image names and tags must be known in advance.
- Found by trying tags: `profiseeplatform:2022r1.0`, `2022r2.0`, `2023r1.0` (tag format `YYYYrN.P`, lower-case r).
- `2023r1.0` = Windows container, `os.version 10.0.17763` (Windows Server 2019), 36 layers, about 4.1 GB compressed,
  built 2025-12-16. A Linux Docker engine cannot run it; on a newer Windows host it needs Hyper-V isolation.
- No 2024-2026 tag found in about 150 tried formats. Ask Profisee DevOps/product for the exact image and tag for the
  release under test, and whether a Linux image exists.
- Cause is the token, not the API: the token server returned `access: []` for catalog and metadata_read, pull for any
  name (matches the system scope map `_repositories_pull`, inference). Per Microsoft Learn, repository-scoped tokens
  can never list the catalog; tag listing needs `metadata/read` in the scope map
  (`az acr scope-map update -r profisee -n <map> --add-repository profiseeplatform metadata/read`). Ask IT for that
  plus the repository names (`az acr repository list -n profisee`).
- Blob downloads redirect to Azure storage: follow the redirect WITHOUT the Authorization header or storage returns 401.

Related: [[project_profisee_db_start_settings_2026-11-20]], [[project_isolation_test_plan_page_2026-11-17]].
