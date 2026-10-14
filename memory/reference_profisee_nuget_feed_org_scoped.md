---
name: profisee-nuget-feed-org-scoped
description: Profisee DevOps NuGet feed is org-scoped; old project-scoped URL (…/profisee/Products/_packaging/…) returns 404 TF1600011
metadata: 
  node_type: memory
  type: reference
  originSessionId: 7d42ab1d-ab7e-4982-9c11-7298fc70bf69
  modified: 2026-08-20T16:11:24.888Z
---

Profisee DevOps NuGet feed moved to **org scope**. Correct URL: `https://pkgs.dev.azure.com/profisee/_packaging/Profisee/nuget/v3/index.json`. Old project-scoped URL (`…/profisee/Products/_packaging/Profisee/…`) returns 404 `TF1600011: The feed with ID 'Profisee' doesn't exist`.

Symptom of stale URL: repeated `[NuGet Manager] [Warning] The plugin credential provider could not acquire credentials` during restore (NuGet treats 404 like auth failure, falls back to CredentialProvider.Microsoft, which can't prompt non-interactively). Restore still succeeds from local package cache, so it's warning spam until a genuinely new package is needed.

Fixed 2026-08-20 in `%APPDATA%\NuGet\NuGet.Config` (URL only; `packageSourceCredentials` DPAPI blob keyed by source name, untouched, still valid). Env vars `Nuget_ProfiseeFeedUserName`/`Nuget_ProfiseeFeedPassword` hold a working PAT for direct API tests.
