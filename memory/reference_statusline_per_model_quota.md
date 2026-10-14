---
name: statusline-per-model-quota
description: "Per-model plan quota (e.g. \"Fable 7d\") is NOT on statusline stdin; it comes from GET api.anthropic.com/api/oauth/usage limits[] weekly_scoped; statusline.ps1 fetches it with the CLI OAuth token, cached 60s; debug dump via marker file"
metadata: 
  node_type: memory
  type: reference
  originSessionId: 449ee42c-7f54-4cad-823e-7080a0eea5cf
  modified: 2026-09-07T00:41:54.912Z
---

Claude Code statusline stdin `rate_limits` carries only `five_hour` / `seven_day` (verified live 2026-09-06,
matches docs). The account-level view that `/usage` renders is `GET https://api.anthropic.com/api/oauth/usage`
with `Authorization: Bearer <claudeAiOauth.accessToken from ~/.claude/.credentials.json>` and
`anthropic-beta: oauth-2025-04-20`. Its `limits[]` has `kind:"weekly_scoped"` buckets labelled by
`scope.model.display_name` — on Gene's account only **Fable** has one (28% on 9/6); `seven_day_opus` and
`seven_day_sonnet` were null. Opus draws only from the shared 5h/7d windows; no per-model share of those is
measured server-side.

`~/.claude/statusline.ps1` (2026-09-06): `GetQuotaBuckets` fetches that endpoint at most every 60s (3s
timeout), caches to `~/.claude/statusline-quota.json` (disposable), renders one `<Model> 7d:` segment per
bucket after `7 Days:`, `~` suffix when serving a stale cache. Stdin debug dump can be enabled on a running
session by touching `%TEMP%\claude-statusline-debug.on` (env var CLAUDE_STATUSLINE_DEBUG needs a restart).

Later the same day all dollar segments (Session/Day/Week) were removed per [[statusline-quota-not-dollars]].
The transcript scanner (`GetUsage`, cache `~/.claude/statusline-usage.json` v3, hour×family buckets) now
renders per-model SESSION tokens (incl. subagents) and a `[Fable 69% Opus 31%]` share of weighted local
usage after each of the 5 Hour / 7 Days segments — attribution, not a quota meter (Claude Code's own
/usage "what's contributing" panel does the same kind of weighted local scan). Price table kept only as
weights; `claude-fable-5-1` added to it (was missing → weighed zero). Cold backfill ≈27 refreshes at ~1.1s
(`~` marker), warm ≈0.5s.
Related: [[reference_prompt_cost_analysis]].
