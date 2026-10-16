---
name: reference-ai-profisee-review-2026-10-14
description: "Review of Martin Perry's ai-profisee Claude plugin marketplace (C:\\devops\\repos\\ai-profisee, ADO): good/bad findings, what to borrow; promotion target for share.yaml"
metadata:
  node_type: memory
  type: reference
  originSessionId: f0454aab-598a-49d1-b5bc-df925330f846
  modified: 2026-10-15T00:42:09.810Z
---

Reviewed 2026-10-14 (full text: session f0454aab transcript, assistant message 17:34:57). Repo = Martin Perry's Profisee
Claude Code plugin marketplace, ADO `profisee.visualstudio.com/Products/_git/ai-profisee`; 23 skills + 2 agents built
into 27 plugins by `build-plugins.sh`, CI drift check, Desktop zips. Clone owned by genewe: git needs
`-c safe.directory=...`.

**Good:** per-plugin install + CI drift check; "owns / hands off to" lines; discover facts at run time; verify by
result not exit code (`dev deployData` exits 0 on failure); Sonar built direct + `-gateway`; strong skills:
`ways-of-working`, `profisee-test-infrastructure`, `dev-machine-profiler`, `gsudo-elevation`.

**Bad:** `squash` needs `resource-coordination` (not in repo; `terminate`, `git-workflow` also missing); `squash` ~900
lines of locking jargon; `programming`/`dotnet` are TODO-only but broad descriptions; `testing` written for Copilot
(`runTests`); hardcoded CORP\MartinPe/AMartinPe, CORPLTR112, Martin's memory/vault paths; NuGet path differs
(`C:\DevOps\LocalNugetPackages` vs `C:\NuGet\Local`); README cites missing `build-plugins.py`; agent pins
`github-copilot/claude-sonnet-4.5`; gotcha tables despite AGENTS.md ban; plugin version pinned 0.1.0 (Claude docs:
installed plugins do not update unless the version changes or is unset) -> coworkers miss updates; raise with Martin.

**Borrow decisions 10/14 (round 1):** gsudo-elevation SKIP (runs elevated by choice, [[feedback-runs-elevated-by-choice]]);
dev-machine-profiler SKIP; ways-of-working SKIP; profisee-api-architecture INSTALL as plugin (marketplace add needs
ADO sign-in: Gene runs `claude plugin marketplace add https://dev.azure.com/profisee/Products/_git/ai-profisee` in a
separate terminal, then `claude plugin install profisee-api-architecture@profisee`). enabledPlugins is seed-only in
the settings template, so CLI installs do not cause drift.
Round 2: SKIP profisee-test-infrastructure, feature-storyboards, windows-powershell-patterns, nuget-troubleshooting,
and the whole platform-dev group. Net: only profisee-api-architecture is borrowed; don't re-propose the rest.

**Since then:** Gene chose NOT to package own skills as plugins (private git repo [[project-ai-setup-private-git-repo-2026-10-14]]);
ai-profisee = target for selective promotion via share.yaml + Promote-ToWork.ps1 (needs git-policy row + safe.directory).
