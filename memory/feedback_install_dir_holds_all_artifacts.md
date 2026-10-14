---
name: feedback-install-dir-holds-all-artifacts
description: "Everything a Speedy install produces — secrets, data, journal, libraries, logs — lives under the install directory (C:\\Deploy\\<App>), never %ProgramData% or %APPDATA%, unless it provably cannot work anywhere else"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 25a6f180-ace3-4c16-9718-60b837d6c54c
  modified: 2026-09-07T23:21:14.840Z
---

**Gene, 2026-09-07 19:19: "Remember the default install is c:\Deploy we want all artifacts under the
install directory like secrets, data, etc do not put them in normal windows locations UNLESS they will
not work anywhere but there — that's why we have an install directory."**

`DefaultDirName={sd}\Deploy\{#AppName}` (`installer/SpeedyAgent.iss:91`), so a standard box installs to
`C:\Deploy\SpeedyAgent`. Secrets, libraries, journal, data and logs all go under `{app}`.

**Why:** one folder is the whole install. Back it up, copy it, delete it, or look at it without knowing
which of four Windows conventions this product happened to pick. The donors scatter (`%ProgramData%\CrewChief\secrets`,
`%ProgramData%\TestAuto`) and [[reuse-donor-installers]] harvests their startup facts, not that habit.

**The exception is narrow and must be argued, not assumed:** things Windows will only honour in a fixed
location — LSA rights, machine environment variables, service registration, the event log, the certificate
store. "The donor put it in ProgramData" is not an argument.

**How to apply in vNext.** No product change is needed — the resolvers already take an explicit path first:
- `Speedy:SecretsFolder` (`SecretsRootResolver.ConfigKey`), then env `SPEEDY_SECRETS_FOLDER`, then the
  `%ProgramData%\Speedy\secrets` service default. The installer sets precedence 1 (and 2, so a CLI run on
  the same box agrees) to `{app}\secrets`.
- `Speedy:Libraries:RootPath`, same shape, to `{app}\libraries`.
- `Speedy:Journal:RootPath` to `{app}\journal`.
The `%ProgramData%` branches stay as the no-installer fallback and are still correct for that case — do not
delete them; just never let an installed box reach them.

**Consequence for row 59.3.** `appsettings.Production.json` is written CREATE-ONLY (D2, the CrewChief seam),
so a later row cannot add keys to it. Every machine-local path must therefore be written in that ONE write
alongside `Speedy:Agent:Roles`, not deferred to rows 59.4/59.6. See [[vnext-installer-purpose]].
