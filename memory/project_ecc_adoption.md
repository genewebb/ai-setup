---
name: project-ecc-adoption
description: "What was taken from the ECC repo on 2026-07-25, what was deliberately rejected, and where it now lives"
metadata: 
  node_type: memory
  type: project
  originSessionId: 875a0862-8f07-47b0-b7a4-40af27dadba8
  modified: 2026-07-25T19:04:02.590Z
---

Reviewed `C:\devopslocal\repos\ECC` ("Everything Claude Code", MIT, Affaan
Mustafa) on 2026-07-25 — 279 skills / 67 agents / 94 commands. It is a
kitchen-sink marketplace plugin; roughly 200 skills are off-domain. The value is
concentrated in ~15 harness-mechanics skills.

**Adopted (7).** Hooks in `~\.claude\scripts\`: `hook-dispatch.ps1` (kill switch
+ single-process dot-source dispatch) and `gateguard.ps1` (DENY→FORCE→ALLOW
fact-forcing gate on first Edit/Write per file per session), covered by
`tests\run-hook-tests.ps1` (16 cases, no Pester — only legacy 3.4.0 is
installed). In `work-ai`: agent `silent-failure-hunter`, skills `config-gc`,
`context-budget`, `blazor-click-path-audit` (from `click-path-audit`),
`inherit-legacy-style`, `dual-review-convergence` (from `santa-method`).

**Rejected, do not re-litigate.** `dotnet-patterns` / `csharp-testing` /
`csharp-reviewer` push xUnit + FluentAssertions + Moq — a direct conflict with
the MSTest + bUnit house stack (see [[project_tech_stack]]). All 94 ECC
`commands/` — ECC's own AGENTS.md calls that surface legacy. ECC's `hooks.json`
architecture — it inlines a 1,200-char `node -e` blob into all 15 entries.
`continuous-learning-v2` — deferred; needs a Python CLI plus a background daemon
that writes autonomously.

**Deferred follow-ups:** profile-scoped linker (`-Profile speed-merchants|crewchief`)
for trigger precision, not token savings; a warn-only rationalization-regex Stop
hook from `delivery-gate`; optional `confidence:` / `scope:` frontmatter on
`feedback` memories.

**Worktrees were assessed and rejected for harness work** — `~\.claude` is not a
repo at all, and `work-ai` is Obsidian-synced with a remote-less stale git, where
a worktree would sync as a duplicate skill tree. The open question is whether they
pay off in speed-merchants (expensive `dotnet build`, test runs that lock
`TestAuto.Web.dll`); see [[feedback_no_worktrees]] before changing that rule.

Plan and execution log: Work vault `52 Technical\AI\ClaudeCode\Plan_ECC_Adoption.md`.
See [[reference_claude_hook_activation]] and [[project_repos]].
