---
name: reuse-donor-installers
description: "Gene: for the vNext agent installer + Windows-service block (rows 59.x), harvest from the existing TestAuto / CrewChief / TestData installers instead of writing anything new"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 25a6f180-ace3-4c16-9718-60b837d6c54c
  modified: 2026-09-07T19:59:54.380Z
---

**For the vNext installer and Windows-service block (schedule rows 59.1 through 59.9), take what is good from
the installers and service hosts that already ship, rather than reinventing.** Gene, 2026-09-07 15:58: "We
already have an installer for a windows service and install of the other solutions from TestAuto, CrewChief,
Data Generation, etc. I would say take anything good from them rather than reinventing the wheel."

**The donors live in a DIFFERENT repo:** `C:\devops\repos\speed-merchants` (hyphenated — the TestAuto and
CrewChief solution), not `C:\devops\repos\speedmerchants` (vNext). Read them with
`git -C C:\devops\repos\speed-merchants show HEAD:<path>` so the working tree is never touched.

What each donor already solved, and which skill holds the tested detail:

| Donor concern | Where the pattern is written down |
| --- | --- |
| Inno script shape, service-or-shortcuts install, the service-account page, the secrets-folder ACL, `sc failure` + `sc failureflag` recovery, the ISCC 7→6 compiler ladder, the never-change AppId | [[inno-setup-installer]] skill; `installer/TestAuto.iss`, `CrewChief/installer/CrewChief.iss` |
| Running the SAME binary interactively and under the SCM: pin the current directory (the SCM starts you in `System32`), an `AppDomain.UnhandledException` breadcrumb file (the only channel that survives an SCM 1053 death, because the log sink does not exist yet), pin the content root, decide service-mode ONCE and publish it as an immutable marker, never block on an interactive prompt | [[testauto-windows-service-hosting]] skill |
| `SeServiceLogonRight` through the LSA API | `Grant-ServiceLogonRight.ps1` (byte-identical in both donor installers) |

**Why:** every one of those facts is a scar from a real failure — a service dying silently in `System32`, an
SCM start-timeout at event 7009 that recovery actions alone do not cover, antiforgery breaking on restart.
Re-deriving them means re-earning them. See [[testauto-service-boot-7009-timeout]].

**How to apply:** `vNext\Design\Installer_Plan.md` §0 ALREADY censuses nine donor files for the installer rows
(59.2 onward), so those rows are covered. **Row 1 / 59.1 was the gap** — it planned only a package reference,
`UseWindowsService()` and a `serve` verb, and skipped the donor's startup preamble entirely. Amended
2026-09-07. When planning any row in this block, name the donor file and line range the row harvests from, and
say explicitly what is web-only and must NOT be ported into the headless agent.
