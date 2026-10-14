---
name: context-budget
description: >
  Token-cost audit of everything loaded into a Claude Code session — skills,
  agents, rules, MCP tool schemas, CLAUDE.md, and MEMORY.md — producing a ranked
  list of what to trim and how much it saves. Use when asked how much context is
  being consumed, before adding more MCP servers or skills, when output quality
  degrades in long sessions, or as the measurement pass that precedes a config
  cleanup.
---

# Context Budget

Measure what the harness costs before deciding what to cut. This is the
measurement half of the cleanup lifecycle; `config-gc` is the action half.

## When to Use

- "How much context am I burning?" / "do I have room for N more MCP servers?"
- Before adding a batch of skills or a new MCP server
- Output quality degrading in long sessions
- As step 1 of a config cleanup, to rank what `config-gc` should propose

## Read This Before Reporting

**Be honest about which lever actually matters.** On a 1M-context model with
~140 skills, the always-loaded cost is dominated by MCP tool schemas, not skills:

| Component | Always loaded? | Rough cost |
|---|---|---|
| Skill `description` frontmatter | Yes, all of them | ~60–90 tokens each → **~8–12k total** |
| Skill body (`SKILL.md`) | No — only when invoked | 0 until triggered |
| Agent `description` | Yes | ~40–80 tokens each |
| Agent body | No — only when spawned | 0 until spawned |
| MCP tool schemas | Yes, every tool | **~500 tokens per tool** |
| `CLAUDE.md` chain | Yes | full file |
| `MEMORY.md` | Yes | full file |

So: **one 30-tool MCP server costs more than the entire skill corpus.** Say this
in the report. Do not let a reader conclude that deleting skills is the big win.

The real reason to prune skills is **trigger precision** — fewer wrong-domain
skills competing for activation means fewer misfires. That is a quality
argument, not a token argument. Report it as such.

## Phase 1 — Inventory

```powershell
$w = '{AIWorkRoot}'

function Get-FrontmatterCost {
    param([string]$Path)
    $c  = Get-Content $Path -Raw
    $fm = if ($c -match '(?s)^---\r?\n(.*?)\r?\n---') { $Matches[1] } else { '' }
    [pscustomobject]@{
        Name       = Split-Path (Split-Path $Path -Parent) -Leaf
        BodyTokens = [math]::Round($c.Length / 4)
        DescTokens = [math]::Round($fm.Length / 4)
        Lines      = ($c -split "`n").Count
    }
}

$skills = Get-ChildItem "$w\skills" -Directory | ForEach-Object {
    $p = Join-Path $_.FullName 'SKILL.md'
    if (Test-Path $p) { Get-FrontmatterCost $p }
}

'{0} skills | always-loaded (descriptions) ~{1} tokens | on-demand (bodies) ~{2} tokens' -f `
    $skills.Count,
    ($skills | Measure-Object DescTokens -Sum).Sum,
    ($skills | Measure-Object BodyTokens -Sum).Sum

Write-Output "`n--- 15 heaviest bodies (on-demand cost when invoked) ---"
$skills | Sort-Object BodyTokens -Descending | Select-Object -First 15 Name, Lines, BodyTokens

Write-Output "`n--- bloated descriptions (>120 always-loaded tokens) ---"
$skills | Where-Object DescTokens -gt 120 | Sort-Object DescTokens -Descending |
    Select-Object Name, DescTokens
```

Then the always-loaded flat files:

```powershell
$always = @(
    "$env:USERPROFILE\.claude\CLAUDE.md"
    "$env:USERPROFILE\.claude\projects\C--devops-repos-speed-merchants\memory\MEMORY.md"
)
$always | Where-Object { Test-Path $_ } | ForEach-Object {
    $c = Get-Content $_ -Raw
    [pscustomobject]@{
        File   = Split-Path $_ -Leaf
        Lines  = ($c -split "`n").Count
        Tokens = [math]::Round($c.Length / 4)
    }
} | Format-Table -AutoSize
```

Agents use the same shape against `$w\agents\*.md`.

## Phase 2 — MCP tool census (the dominant line item)

Count the tools each connected server exposes and multiply by ~500 tokens.
Enumerate from the live tool list, not a config file — the config does not say
how many tools a server exposes.

Flag:

- Any server with **>20 tools**
- **Functionally duplicate servers** — near-identical tool sets pointed at
  different environments. A local/remote pair of the same MCP costs double for
  one capability; consider keeping only the one in active use.
- Servers that **wrap a CLI already available** (`git`, `gh`, `az`) — the CLI is
  free, the schemas are not
- Servers that **fail to connect** — they may still cost schema tokens

## Phase 3 — Classify

| Bucket | Criteria | Action |
|---|---|---|
| **Always needed** | Matches the current repo's stack; referenced by `CLAUDE.md`; backs an active workflow | Keep |
| **Sometimes needed** | Domain-specific but off the current project (e.g. `crewchief-*` while working in speed-merchants) | Candidate for profile-scoped loading |
| **Rarely needed** | No match to any active project; overlapping content | Retire via `config-gc` |

For a corpus split across projects, state the split explicitly. `testauto-*` and
`crewchief-*` are each irrelevant to the other project, so on any given day a
large fraction of descriptions are dead weight **for activation purposes** even
though their token cost is modest.

## Phase 4 — Report

```text
Context Budget
==============
Model / window:            <model>, <window>
Always-loaded overhead:    ~XX,XXX tokens  (X.X% of window)

  MCP tool schemas   N tools across M servers   ~XX,XXX   <- usually dominant
  Skill descriptions N skills                   ~X,XXX
  Agent descriptions N agents                   ~XXX
  CLAUDE.md chain                               ~X,XXX
  MEMORY.md                                     ~X,XXX

On-demand (only when invoked):
  Skill bodies       N skills                   ~XX,XXX
  Agent bodies       N agents                   ~XX,XXX

Findings (ranked by tokens saved):
  1. <action>  -> ~X,XXX tokens
  2. <action>  -> ~X,XXX tokens

Trigger-precision findings (quality, not tokens):
  - <N> skills belong to a project other than the current one

Recommendation: <one sentence>
```

Always separate the two finding types. Conflating "saves tokens" with "reduces
misfires" is how a report ends up recommending the wrong thing.

## Estimation Rules

- Prose and code alike: `characters / 4`. Close enough for ranking, which is
  all this needs.
- MCP tool schema: ~500 tokens each — an order-of-magnitude estimate.
- **Never present estimates as measurements.** Write "~", say "estimated", and
  state what the estimate is based on.

## Anti-Patterns

- **Reporting skill-body totals as if always loaded.** Bodies load on
  invocation. Conflating the two overstates skill cost by an order of magnitude.
- **Recommending deletion on token grounds** when the real problem is trigger
  collision.
- **Auditing without acting.** Hand findings to `config-gc`, which owns the
  confirm-each-item workflow and the undo log.

## Related Skills

- `config-gc` — the action half. Run this first to rank, that second to reclaim.
- `skill-audit-with-update` — quality of individual skills, not aggregate cost.
- `permissions-yaml` — permission entries are config bloat but cost no context;
  they do not belong in this report.

---

Adapted from ECC (MIT, © 2026 Affaan Mustafa) — <https://github.com/affaan-m/ECC>
