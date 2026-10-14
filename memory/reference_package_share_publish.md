---
name: package-share-publish
description: dpspeed/dpcrewchief/dpdatagen/dpmutate -Package and dpall auto-copy the built Setup exe to the UNC share \\CORPNAS01\RnD\Utilities\SpeedMerchants and prune strictly-older versions of the same product there (version-aware since 2026-08-13); the UPLOAD is the slow part, not the prune, because the share is reached over a ~25ms VPN tunnel at ~1.8 MB/s (batched, skip-if-identical, parallel since 2026-08-25)
metadata: 
  node_type: memory
  type: reference
  originSessionId: f55edf44-80e4-4cc6-aeb0-d3c5a7423aa7
  modified: 2026-09-14T14:56:49.185Z
---

**Drop folder is `C:\Bits` since 2026-09-14** (was `C:\tmp`; mentions of C:\tmp below are historical). Single constant `$global:GeneBitsDir` in the profile; the four `-Package` wrappers and `dpall` pass it as `-OutputDir` to the `New-*Installer.ps1` scripts (whose own default is still `C:\tmp` - running a repo script bare drops there); `-Update` zips (profile `dpmutate` + `Gene.DevOpsTools` `Get-GeneBitsZipPath`) and `dpall -Parallel` logs also go there.

The pwsh profile (`C:\Users\agenewe\Documents\PowerShell\Microsoft.PowerShell_profile.ps1`) has `Publish-SpeedMerchantsPackage` (defined just before `dpspeed`): after a successful `dpspeed -Package` or `dpcrewchief -Package` (with or without -Bump) it copies the newest freshly-built `<Product>-Setup-*.exe` from `C:\tmp` to the share and prunes `<Product>-Setup-*.exe` files from BOTH C:\tmp and the share (other product's packages untouched). **Prune is version-aware since 2026-08-13**: version parsed from the filename, only STRICTLY-OLDER packages removed — a newer package already on the share is kept with a warning, so a downgrade rebuild cannot destroy it (previously it pruned by name-inequality and would have). Unparseable names are kept and warned about. `-BuiltAfter` timestamp gate prevents re-publishing a stale exe after a failed build (the packaging scripts throw on failure, so the call is only reached on success). Unreachable share → warning only, package stays in C:\tmp.

**The destination is the UNC path `\\CORPNAS01\RnD\Utilities\SpeedMerchants`, NOT `Z:`.** Z: is a per-logon-token mapped drive: an elevated shell cannot see the non-elevated Explorer session's mapping, and `net use` will report it `Unavailable` with `Get-PSDrive` omitting it entirely — even though the UNC path resolves fine from the same shell. `EnableLinkedConnections=1` is set on CORPLTR94 but only takes effect at logon, so a mapping made after logon doesn't propagate to the admin token. Diagnostic order: `Test-Path` the UNC first — if that works, the share is fine and only the drive letter is stale. Never reintroduce `Z:` into these scripts or their help text.

**The copy only fires under `-Package`.** There is no `-Publish` switch on either command. Since 2026-08-13 a bump switch without `-Package` THROWS in both commands (previously silently inert), multiple bump switches throw in the wrapper (so `-WhatIf` refuses like a real run), and `dpcrewchief -Cli -Package` throws. Correct invocation is `dpcrewchief -Package -Bump` with SINGLE dashes — `--Bump` does not bind (PowerShell binds single-dash switch names only). `dpcrewchief` has a `ValueFromRemainingArguments` `$CliArgs` catch-all that used to silently swallow `--Publish`/`--Bump` and fall through to the default build+publish+run path with no error; a guard added 2026-07-31 now throws on leftover args whenever `-Cli` is absent (the `--sealsecret`/`--seal-secret`/`--unlock` token forms still work because the guard sits after their early-return), and since 2026-08-13 its known-switch hint list is DERIVED from param() metadata rather than hand-copied (the hand copy had silently missed BumpMinor). `dpspeed` needs no guard — it has no catch-all and errors on its own.

## Share-tail performance work, 2026-08-25

**The prune was never the slow part.** Measured on CORPLTR94: share delete of an 81 MB exe 0.84s, share listing 0.48s, stage-dir delete (1113 files / 257 MB) 1.03s via `Remove-Item -Recurse`. The cost is the UPLOAD — `Copy-Item` of 81 MB to the share took 44.5s at ~1.8 MB/s. Because the "Removed older package from share" lines print immediately AFTER that silent 44s copy, the removal step looks slow and gets the blame. Four serial products in `dpall` = ~188s of share tail.

**Root cause of the ~1.8 MB/s: CORPNAS01 (10.36.55.17) is reached over the Always On VPN Device Tunnel, not the LAN** (local IP was 192.168.8.249, RTT ~25ms, NIC link 1 Gbps, SMB 3.1.1 signed-not-encrypted). SMB over a 25ms tunnel is the whole explanation — it is not a NAS problem and not fixable in the scripts. Four parallel streams recovered only **1.47x** (50.1s -> 34.0s for 4x20 MB), so the tunnel is close to a hard aggregate cap (~1.6-2.4 MB/s); do NOT expect parallelism to scale here. On the corporate LAN the cost should largely disappear. Untested client-side knob worth trying: `Set-SmbClientConfiguration -EnableBandwidthThrottling $false` (Windows throttles SMB on links it judges to be WAN; currently `True`).

**What changed.** `Publish-SpeedMerchantsPackage` `-Product` widened `[string]` -> `[string[]]`, and `dpall` now hands over ALL succeeded products in ONE call (filtering ValidateSet-unsupported products out first, since one unknown name would fail the whole batch). That enables three things:
- ONE share listing per batch, which doubles as the reachability probe — the separate `Test-Path $share` is GONE (it was the expensive 1.22s half of the old 1.7s-per-product pair).
- Upload SKIPPED when the share already holds the same filename at the same byte `Length`. This is the big win: a no-bump repackage used to re-upload ~81 MB per product for nothing.
- Remaining uploads run in parallel via `ForEach-Object -Parallel` + `robocopy` (not `Copy-Item`, so a runspace needs no profile state). robocopy exit codes **< 8 are success**; a product whose upload failed is skipped by the share prune so a failed copy never deletes the version it was replacing.

The share prune reads the PRE-RUN snapshot deliberately: it only considers packages that existed before the call, so it can neither see nor delete a sibling product's fresh upload.

Measured after: three byte-identical products completed in **0.54s** with the share untouched (was ~141s).

**Selection of "the build" is by newest `LastWriteTime`, not by version.** Pre-existing behaviour, not a regression, but it means a newer-mtime-but-older-version exe sitting in `C:\tmp` will be treated as the build; it then safely warns and keeps everything newer rather than deleting it. A prune test that creates fixture files without stamping mtimes will pick the wrong "build" and produce confusing failures.

Also 2026-08-25, in all four `New-*Installer.ps1` scripts: the stage-dir clean is now `[System.IO.Directory]::Delete($stageDir, $true)` with `Remove-Item -Recurse -Force` as a `catch` fallback (0.52s vs 1.03s; the .NET call throws where `-Force` would have won). Worth ~0.5s each — marginal, done for completeness.

Rejected as measured-worthless: `robocopy /J` in place of `Copy-Item` for throughput alone (2.2 vs 1.8 MB/s — robocopy is used for the runspace-isolation reason, not speed). Defender exclusions were NOT added (user skipped); note `(Get-MpPreference).ExclusionPath` is empty on this box, so publish/ISCC compile are unexcluded — never measured, so no claim about the size of that.

See [[feedback_verify_no_guessing]].
