---
name: reference-version-scheme-unified
description: "CrewChief and TestAuto both use Major.Minor.Patch with identical -Bump/-BumpMinor/-BumpMajor switches (aligned 2026-08-12); TestAuto's old Major.Minor + timestamp Build.Revision scheme is gone"
metadata: 
  node_type: memory
  type: reference
  originSessionId: c75df020-a35f-4f1b-aa5b-9c75d9958a63
  modified: 2026-08-12T17:53:59.188Z
---

**Both products use Major.Minor.Patch. Aligned 2026-08-12 — do not cite `VersionMajor`/`VersionMinor` or timestamp-derived `Build.Revision` for TestAuto; those properties no longer exist.**

Single sources of truth (both hand-maintained, bumped every ship — always re-read, never quote the number):
- CrewChief: `<Version>` in `CrewChief\Directory.Build.props`
- TestAuto: `<Version>` in `TestAuto.Web\TestAuto.Web.csproj`

Identical switch semantics in `New-CrewChiefInstaller.ps1` and `New-TestAutoInstaller.ps1` (and both `dp*` wrappers): `-Bump` = patch, `-BumpMinor` = minor + reset patch, `-BumpMajor` = major + reset the rest; more than one throws.

**Why 3-part won:** TestAuto had no patch slot, so every hotfix burned a Minor (1.9 → 1.14 → 1.32 → 1.34 → 1.50). Both the installer (`$shortVersion`) and `AppVersionInfo.ToDisplayVersion` truncated the timestamp components away, so they were never release identity — the build timestamp operators actually want was already carried out-of-band by the `StampBuildDate` target as `AssemblyMetadata("BuildDate")` → `AppVersionInfo.BuildDateUtc`. Dropping the computed parts cost nothing.

**Update-feed consequence:** the in-app banner (`UpdateCheckService`) compares `System.Version` values parsed from the feed filename, so a PATCH bump is now a releasable update. Under the old 2-part scheme a hotfix needed a fake Minor bump to be visible. Same-version rebuilds are still invisible — bump when you mean to release. `2.5.0 > 2.5` under `System.Version` (Build 0 beats -1), so boxes running the old 2-part 2.5 see 2.5.0 as newer.

**New guard in the TestAuto packaging script:** after publish it re-reads `FileVersion` off the built `TestAuto.Web.dll`, normalizes to 3 components, and **throws if it disagrees with the csproj** — a stale stage or an unbuilt `<Version>` edit can no longer ship a package whose filename lies about the app inside it. CrewChief has no equivalent check (it names the package straight from the props file).

**Duplication is deliberate:** the bump blocks are copy-paired, not shared, because CrewChief's installer must not reference anything on the TestAuto side ([[project_crewchief_standalone]]). Both carry a "change one, change the other" comment. Editing one half alone silently re-introduces the mismatch.

Display path: `AssemblyInformationalVersion` (with any `+<git-sha>` trimmed) → 3-part trim → shown in TestAuto's Help → About + home Version pill (`AppVersionInfo`) and CrewChief's Home pill (`Home.razor.cs:ResolveProductVersion`, which got the same trim so its assembly-version fallback can't render 4 parts).

See skill `inno-setup-installer`, and [[project_testauto_service_install_plan]] (whose "version floor 1.50 / Major.Minor only" notes are superseded by this).
