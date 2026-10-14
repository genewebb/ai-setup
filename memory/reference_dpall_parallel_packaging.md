---
name: reference_dpall_parallel_packaging
description: dpall profile command packages all four SpeedMerchants products in parallel; why parallel is safe and what makes it work
metadata: 
  node_type: memory
  type: reference
  originSessionId: ab8eb3ac-edb3-42cb-af32-ab97cc8d4d39
  modified: 2026-08-25T14:04:19.140Z
---

`dpall` (PS7 profile, `Microsoft.PowerShell_profile.ps1`, added 2026-08-25 after `dpmutate`) packages all four products in one command: `dpall [-Products speed,crewchief,datagen,mutate] [-Bump|-BumpMinor|-BumpMajor] [-Configuration] [-Parallel] [-SkipShare] [-WhatIf]`. **Default is SERIAL** — user's call, four concurrent self-contained publishes saturate the laptop for a sublinear win. `-Parallel` is the opt-in. Bump level is uniform across selected products by design — per-product bumps stay in `dpspeed`/`dpcrewchief`/`dpdatagen`/`dpmutate`.

**Why parallel is safe:** the four trees are disjoint — no shared `ProjectReference`, separate `installer\stage`, separate `<Version>` file, product-distinct exe names in `C:\tmp`, and per-product prune filters. Verified live 2026-08-25: concurrent `datagen`+`mutate` run, both clean, concurrent ISCC 7 compiles no conflict (1:15 / 1:36).

**Two non-obvious implementation constraints:**
- Background jobs run in a fresh pwsh with **no profile**, so `dpall` calls each `New-*Installer.ps1` directly — the `dp*` wrappers do not exist in the job. The installer scripts are profile-free by design, which is what makes this legal.
- The job scriptblock **collects** merged output (`*>&1`) into a list and writes it in `finally`, not `| Out-File` — a pipeline to a file loses its buffer when the upstream command throws, producing an empty log exactly when a build failed.

Share copy/prune runs serially in the parent via `Publish-SpeedMerchantsPackage` (lives in the profile, unavailable in a job), one `-BuiltAfter` stamp for the whole run. Failures throw only after the summary and share tail, so a broken product never strands the others' packages.

Related: [[reference_package_share_publish]], [[feedback_no_profile_commands_in_docs]] (never cite `dpall` in repo docs).
