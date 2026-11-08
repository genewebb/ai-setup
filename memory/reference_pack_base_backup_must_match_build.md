---
name: reference-pack-base-backup-must-match-build
description: 400 DATA00030 / 403 CNX00080 after a restore = the backup was configured before the LAST Profisee Configuration on that app server (stale service sign-in ids); every pack test now configures its base at run start
metadata:
  node_type: memory
  type: reference
  originSessionId: 95f5b98f-d94c-408a-8901-e309c3b37709
  modified: 2026-11-08T20:20:51.504Z
---

**Symptom:** after restoring a pack base, GET v1/Rules = **400 DATA00030 "User Is Invalid"** (Matching: 403 CNX00080),
while the gateway check (v1/Entities) passes, the API key is set (1 row) and CORP\speedmerchants is Super Administrator.
Profisee log (logging.tSystemLog) shows the decisive line: `No client with id '<32 hex>' found` + `invalid_client`.

**Root cause (found 11/08 15:00):** Profisee Configuration writes NEW service sign-in ids (meta.tUser.ClientId of all 12
service users + the API user, encrypted, 172 chars) into the database it runs on AND into the application server. So only
the backup configured LAST works. 11/08: CRUD base configured 10:32, Matching base 10:38: Matching passed, CRUD failed.
My first two theories were wrong: "IIS restart" and "base on old build" (old build was part of it on 11/07, but a
same-build base configured earlier also fails). `auth.Clients` is empty in EVERY base: not the cause.

**Fix (Gene 11/08: "restore base, run Configuration, confirm, set API key, clean backup to fall back on", once per pack
run):** CRUD `crud-run-start` first in every crud-test-* (restore base, install-configure-upgrade, health, IIS stop, key,
IIS start, gateway + Data checks, base check, back up `profisee_CRUD_run-start.bak`); `crud-base-reset` restores the
run-start copy. Matching: each load restores the empty baseline and runs install-configure-upgrade before the key.
install-base-upgrade removed; base files never overwritten.

**Rules learned:**
- Check `No client with id` in tSystemLog before blaming the key: the key is fine, the service ids are stale.
- One API key and one user (CORP\speedmerchants) for every pack (Gene).
- CRUD, Matching and Install packs are GENERATED (ai-setup gen_crud.py, gen_sizes.py, gen_install.py): change the
  generator, regenerate, Test-Pack.ps1 must PASS.
- Test-Pack resolves a RunWorkloadStep child from a sibling pack; a box running CRUD/Matching tests needs the install pack.

Related: [[project-test-lab-topology-cadence]], [[feedback-red-is-red-declared-inputs]]
