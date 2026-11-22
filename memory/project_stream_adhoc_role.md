---
name: project-stream-adhoc-role
description: "stream-adhoc role (owner 2026-10-11): interactive tab per repo, owner requests from requirement to commit, closed groups only; commits itself via Commit-AdhocChange.ps1; addStreamTab -Role <any role>"
metadata:
  node_type: memory
  type: project
  originSessionId: 28c88d04-48e0-401b-b479-5ac38afd10e0
  modified: 2026-10-12T18:08:31.185Z
---

Owner asked 2026-10-11 for an "Adhoc" stream agent for ad-hoc change requests (mostly UI tweaks, changes no group picked up).

Owner answers that shape it:
- Long interactive session, ONE per repo; requests typed in its tab only (no stream-adhoc inbox).
- Adhoc commits itself, only through `stream-kit\scripts\Commit-AdhocChange.ps1` (holds integrate-patch.lock + main-grader.lock, applies to main, dotnet build sln + targeted `dotnet test --filter`, commits only patch paths, reverses on red; recovery cases 116a-f).
- Requirements in the real corpus (`docs\requirements`, requirements-writing skill); requirement + mockup approval before any code.
- Finished = group state `closed`. Future-group work = requirement + stream-plan inbox item, no code.
- File also in an unfinished task's write set: EDIT anyway, then file a stream-plan item per task.
- Test: bUnit/unit; ASK owner per change whether a Playwright test is wanted (long running). No suites.

Launcher: profile `addStreamTab -Role Planner|Integrator|Kit|Coordinator|Status|Author|Builder|Adhoc -Repo <repo>`
opens any role one at a time; addStreams never opens Adhoc. The profile
(Documents\PowerShell\Microsoft.PowerShell_profile.ps1) is NOT in the corpus; backup .bak-202610111906.

Gotchas (2026-10-12, ADHOC-20261012-1; also in `.streams\lessons\adhoc.md`):
- Write `.streams\adhoc\<Id>.md` BEFORE `git worktree add`; watchdog reaps an ADHOC-* tree with no request file after 10 quiet min.
- Commit-AdhocChange.ps1 mangles non-ASCII (ibm437 console capture of git diff), so it answers REBASE forever. Call it from pwsh after `[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)`. Kit bug IN-20261012180815-5151.
- Retiring a feature: target status RETIRED + status_reason; candidate EXCLUDE/RETIRED with mapping included:false; target coverage rows referencing excluded BEH go treatment `retire` + decision_ref (validator rule 1).

**Why:** owner wants ad-hoc tweaks handled end to end without planner/author/builder churn.
**How to apply:** the Adhoc skill text lives in corpus skills\stream-adhoc\SKILL.md; change it via Publish-KitFile.
