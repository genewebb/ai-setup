---
name: reference-stream-cost-transcript-facts
description: "Verified 2026-10-05 on SMVMTR1: Claude transcript cost parsing needs dedupe on (sessionId, message.id) and must recurse <project>\\<sid>\\subagents\\; tasks.json `base` is written only by New-TaskWorktree (1 of 120 tickets had it); spec at vault speedy\\stream-kit\\2026-10-05-priority-focus-design.md"
metadata:
  node_type: memory
  type: reference
  originSessionId: 13fde314-705f-4304-9b61-48985e207b51
  modified: 2026-10-06T16:08:37.916Z
---

Facts measured 2026-10-05 (laptop reading `\\SMVMTR1\c$\Users\speedmerchants\.claude\projects\D--devops-repos-speedmerchants`):

- Transcript assistant lines REPEAT per `message.id` with identical `usage` (sample: 10 lines, 6 ids; integrator file 194 lines, 130 ids). Summing naively overstates spend 1.5-1.9x. Dedupe on `(sessionId, message.id)`, last wins.
- Subagent spend lives in `<project>\<sessionId>\subagents\agent-<id>.jsonl` (1075 files, 676 MB vs 499 top-level, 1158 MB); lines carry parent `sessionId`, `isSidechain: true`, `agentId`. Top-level files hold zero sidechain lines.
- Usage fields: `message.model`, `message.usage.{input_tokens, output_tokens, cache_read_input_tokens, cache_creation.ephemeral_5m_input_tokens, cache_creation.ephemeral_1h_input_tokens}`, `output_tokens_details.thinking_tokens`.
- Runner unit results (`.streams\logs\runner\<runner>\*.json`) carry `session_id`, `session`, `role`, `outcome`, `total_cost_usd`. Long `/loop` sessions record no Claude session id anywhere under `.streams`.
- `tasks.json` row `base` (`{worktree, head, mainDiff, untracked, deps, at}`) is written only by `New-TaskWorktree.ps1` via `Update-Task.ps1 -Base`; a freshness check must key on the latest `history[to=ticketed].at` + `git rev-list -1 --before`, not on `base`.
- Rows must never leave `tasks.json`: `Get-Task` throws on a missing id and `Get-BoardProblems` emits `UNKNOWN-DEP`, refusing every `Revise-Task` batch.

- Ledger 10/1-10/5 (measured 2026-10-06, SMVMTR1 `.streams\cost\ledger.jsonl`, $5,284 total): author $2,468, build $2,221. Main-thread Opus = 75%/67% of each; main spend = 46% cache read, 34% 1h cache write, 20% output; avg ~200k ctx/call. Fresh runner prefix ~83k tokens (~$0.42/unit). Verifier ran on Fable until 10/4 ($591). Diagram: `.streams\author-build-cost.html` beside status.html.
- 10/6 FIX: `claude-opus-5` + `claude-sonnet-5` were missing from `cost-prices.json` (1,460 rows at $0, +$253; true total $5,537); Get-StreamCost.ps1 now REPRICES `"usd":null` rows in its rewrite pass. Source of truth for SMVMTR1 scripts = `Q:\...\work-ai\skills\stream-kit\scripts\` (SMVMTR1 skills link to the share); the live table `.streams\cost\prices.json` is copied only on first run, so update it by hand.
- Cost anatomy (10/1-10/5): main-thread spend = 46% cache reads, 34% 1h cache writes, 20% output. Opus 5.5 and Sonnet 5.5 cache reads cost the SAME ($0.20/M), so a Sonnet main thread saves only ~27% of main spend. Fresh runner prefix ~83k tokens (~$0.42/unit); laptop probe 53k = Claude Code floor 32k + user settings/hooks/plugins 16k + MCP 5k + skills list 4k. Harness knobs (docs): `promptCacheTtl`/`CLAUDE_CODE_PROMPT_CACHE_TTL` (5m|1h), `--effort`/`effortLevel` (default medium), `subagentModel`/`CLAUDE_CODE_SUBAGENT_MODEL`, `--setting-sources`, `--strict-mcp-config`.
- Idle-unit leak 10/5: 64 author idle units ($36) from 2 runners; gated roles have NO idle backoff (Start-StreamRunner.ps1 E4 backoff is `if (-not $gated)`), and the owner's "G3 only" ruling lived in `.streams\lessons\author.md` while the gate (focus set) kept offering G4/G5 rows.

Design that uses these: [[project_stream_priority_focus_design_2026-10-05]] (vault `99 Documentation\speedy\stream-kit\2026-10-05-priority-focus-design.md`, revision 2, clean-session reviewed).
