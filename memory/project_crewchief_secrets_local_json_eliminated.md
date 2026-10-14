---
name: project_crewchief_secrets_local_json_eliminated
description: CrewChief secrets.local.json layering REMOVED entirely (Web+CLI); cert thumbprint moved to appsettings.json as a shipped placeholder; all real secrets come only from the /secrets encrypted store
metadata: 
  node_type: memory
  type: project
  originSessionId: bc525bea-d92c-43f1-b02b-dd4de1184b90
  modified: 2026-07-20T01:37:42.342Z
---

2026-07-19: Eliminated the `secrets.local.json` config layering from CrewChief. It was only ever a plain `AddJsonFile` source for non-secret per-machine overrides, but someone had pasted the v2 SecretStore array seed (real creds) into it → `System.FormatException: Top-level JSON element must be an object. Instead, 'Array' was found.` at Web `Program.cs` startup.

**Changes made (working tree; user commits manually):**
- Removed `builder.Configuration.AddJsonFile("secrets.local.json", ...)` from `CrewChief.Web/Program.cs` and `CrewChief.Cli/Program.cs`.
- Deleted both `secrets.local.sample.json` (Web + CLI, git-tracked) and all `secrets.local.json` working copies.
- Removed `secrets.local.sample.json` `<None Include>` from `CrewChief.Cli.csproj`.
- Removed `secrets.local.json` line from `CrewChief/.gitignore`.
- Added `WebUI:Certificate:Thumbprint` to `CrewChief.Web/appsettings.json` as a **shipped non-real placeholder** (`REPLACE_AT_DEPLOY_...`). Overwrite at deploy time. A non-matching/absent thumbprint degrades gracefully to the ASP.NET dev cert (Program.cs ~line 100). Thumbprint is a public identifier, not a secret.

**Design rule now:** the ONLY per-machine deploy edit is the cert thumbprint in appsettings.json. Real secrets (passwords, connection strings, API keys, RemoteRuntime creds) load ONLY from the `/secrets` encrypted store (`%APPDATA%\CrewChief\secrets.json` via `LocalSecretsConfigurationSource`) — populated by the Web UI or `crewchief secrets import`. See [[project_crewchief_secrets_shipped]] and [[project_crewchief_tier_rename]].

**STALE after this change (not yet updated):** the `crewchief-secrets` skill and ~30 references in `CrewChief.Web/Documentation/*.md` + `CrewChief/README.md` still tell users to copy `secrets.local.sample.json` → `secrets.local.json`. Those instructions are now wrong.

The real v2 SecretStore seed (with real creds) was preserved to a scratchpad file `secretstore-import-payload.json` for import via /secrets. Note: `SMVMTR2` password was `@Quto217` while every other box is `@utoQ217` — likely a transposition typo, left verbatim.
