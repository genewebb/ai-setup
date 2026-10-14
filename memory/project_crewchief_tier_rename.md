---
name: project_crewchief_tier_rename
description: "CrewChief Tier-1→Encryption Secrets, Tier-2→Local Secrets rename (code + env var + docs), 2026-07-18"
metadata: 
  node_type: memory
  type: project
  originSessionId: 08e95719-a0d7-4939-83f7-2163348e1d0b
---

The confusing "Tier-1/Tier-2" secrets terminology was renamed EVERYWHERE (2026-07-18): **Tier-1 = "Encryption Secrets"** (the sealed portable RSA key that drives the SetApiKey step), **Tier-2 = "Local Secrets"** (the local install secret store). Older memories/docs that still say "Tier-1"/"Tier-2" mean these.

Renamed code identifiers (all usages): `Tier1UnsealConfigurationSource`→`EncryptionSecretsUnsealConfigurationSource`; `Tier2SecretsConfigurationSource`→`LocalSecretsConfigurationSource`; `SecretsPaths.Tier1Passphrase/Tier2Store/Tier2Master`→`EncryptionSecretsPassphrase/LocalSecretsStore/LocalSecretsMaster`; `LockoutScopes.Tier1/Tier2`→`EncryptionSecrets/LocalSecrets` (string values `"encryptionsecrets"/"localsecrets"`); UI members `SealTier1/UnlockTier1/Tier1Sealed/...`→`EncryptionSecrets*`.

**Env var `CREWCHIEF_TIER2_MASTER` → `CREWCHIEF_LOCAL_SECRETS_MASTER`** — but it's only the *fallback*; the DPAPI-wrapped `master.json` file is the primary unattended-master path, so on a bootstrapped box the rename is inert (nothing to reconfigure). **On-disk file names (sealed/travel/secrets/master/lockout.json) and the encrypted format are UNCHANGED** — only names in code/UI/docs changed. See [[project_crewchief_secrets_shipped]], [[project_secrets_bootstrap_middleware_not_wired]].
