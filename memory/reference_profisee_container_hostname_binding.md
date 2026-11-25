---
name: reference_profisee_container_hostname_binding
description: Profisee Windows container - configure from the COMMAND LINE with every switch (Setup.ps1 env path leaves firstUserClientID blank); the DB is tied to the container hostname; a docker run with a new random hostname makes the Monolith app pool exit (code 1) and WAS disable it. Pin --hostname. Plus other first-run lessons.
metadata:
  node_type: memory
  type: reference
  originSessionId: 7986e46e-eb36-4bdb-a0ee-12f91e19b099
  modified: 2026-11-25T02:48:37.493Z
---

Found 2026-11-24 on app VM 9302 (CorpProxMox01, `profiseeplatform:2026r3.0-win25`, process isolation):

- **Hostname binding:** after `docker rm` + `docker run` against an existing Profisee DB, app pool `Profisee-Api`
  (Monolith, `C:\Profisee\Services\Monolith`) exits with code 1 about 4 s after start, 5 times, then WAS disables it
  (System 5011 data 0x8007006D, then 5002). No crash events, nothing in `logging.tSystemLog`. Recreate with the
  ORIGINAL container hostname (`--hostname <old>`) = Healthy. Always pin `--hostname` (<=15 chars) from the first run;
  a DB created under a random name needs that name forever (or a rebuild). Gene 21:38: pinned `CPM01-PROFC1`, DB rebuilt.
- **DB create:** configuration expects to create the DB itself. Pre-sized DB fails `MODIFY FILE failed. Specified size
  is less than or equal to current size` (5039). An empty DB with DEFAULT sizes works (ADR/optimized locking set before
  is fine). No DB at all with a non-creating login fails 4060. Create step takes about 10 min on CorpProxMox01.
- **Services call their own external URL** (`ProfiseeExternalDNSUrl`/profisee/auth/.well-known...): Workflow cannot start
  until that URL answers and its TLS cert is trusted inside the container (preinit.ps1 importing the cert to Root).
- **File repository required** for Workflow (`missing workflow file repository configuration`) and FileAttachments
  (`storage_health_check: Failed to write test file`); `/rest/health` stays 503 without it.
- Setup.ps1 re-runs configuration on every container start (`docker restart` too), about 2 min with an existing DB.
- **Configure from the command line, never Setup.ps1's variables (Gene 2026-11-24 22:24).** Setup.ps1 passes
  `firstUserClientID` only from an unset env var, so ConnEx/Data `ClientId` ends up blank and 12 services fail with
  `The ClientId field is required` on a reconfigure. Working recipe: preinit sets `$global:doRunStartupScript = $false`;
  `docker exec` runs `C:\Profisee\Configuration\Profisee.MasterDataMaestro.Services.Configuration.exe` (working dir =
  its folder) with all 41 switches incl. `firstUserClientID` = `UserCredentials:ProfAdminClientId` (Gene 22:30).
  Container then needs NO configuration env vars (no secrets in `docker inspect`). Scripts + README:
  `docs\isolation\profisee-phase\scripts`. Result 23:00: `/rest/health` 200, all 20 checks.
- File repository needs a real account: local container user (`ProfiseeRepo`, password in secrets
  `CorpProxMox01Profisee:FileRepoPassword`) with Modify on the folder, Interactive. IIS_IUSRS rights alone are not enough.
  Change repository settings only on a FRESH container (LoadConfig re-reads them from Monolith settings on reconfigure).
- **Sign-in (2026-11-24 23:25):** redirect URI the app sends = `https://corpproxmox01.corp.profisee.com/profisee/auth/federation/Azure/signin`
  (LOWERCASE `profisee`). Peer app 7a0c8d21 (tenant profisee1.onmicrosoft.com) lacks it: AADSTS50011 after the password.
  `speed.merchants@profisee.com` is NOT an account in that tenant. Users via REST: `PUT /v1/Accounts` with name in
  `identifier.name`; role update needs the account's full identifier AND the role's real `id`/`internalId` (Super
  Administrator = `meta.tUserRole` ID 1); name-only role -> FK error 547. gene.webb@profisee.com is Super Admin there.
- `docker exec` strips quotes from inline `-Command`; use `-EncodedCommand`.
- Image exposes only port 80; TLS has to end in front (here IIS + ARR on the VM). See [[project_isolation_decisions_2026-11-23]].
