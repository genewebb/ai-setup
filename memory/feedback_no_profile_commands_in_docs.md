---
name: feedback_no_profile_commands_in_docs
description: "Repo/product documentation (CrewChief + TestAuto) must never reference the user's personal profile commands (dp*) or devopslocal paths — document the normal dev steps only"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 1972b516-f552-4d7c-a424-c78cb065beeb
  modified: 2026-07-22T13:41:03.203Z
---

Repo and product documentation — README, in-repo `Documentation/` (which ships as in-app help),
DeveloperPack, installer guides, code comments — must contain **zero references to the user's
personal PowerShell profile commands** (`dpcrewchief`, `dpTestAuto`, any `dp*` wrapper) or personal
machine paths (`C:\devopslocal\...`). Direct quote: "my profile are just productivity enhancements
for me."

**Why:** other developers don't have the profile; a doc referencing `dpcrewchief` produces
"command not found" and hides the real workflow.

**How to apply:** always write the normal dev steps — shipped CLI verbs (`crewchief seal-secret` /
`unlock` / `secrets status`), standard `dotnet build/run/test/publish`, or repo scripts
(`installer/New-CrewChiefInstaller.ps1`). When encountering an existing `dp*` reference in docs,
replace it outright (no "profile shortcut" footnotes). Sweep check: grep the repo (md/ps1, excluding
bin/obj) for `dpcrewchief|dpTestAuto|devopslocal` → should be empty. Scrubbed 2026-07-22 (6 files:
Documentation 02/35/37/40, installer/BUILDING.md, New-CrewChiefInstaller.ps1). Rule also codified in
the `ai-foundational-rules` skill (Rule 5) and `testauto-help-docs` checklist. Canonical run-locally
+ build-installer docs for other devs: `CrewChief.Web/Documentation/00_GettingStarted.md` and
`installer/BUILDING.md`.
