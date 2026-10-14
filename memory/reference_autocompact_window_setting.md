---
name: reference_autocompact_window_setting
description: Claude Code has no percentage auto-compact; `autoCompactWindow` (settings.json, 100000–1000000 tokens) set to 500000 on 2026-09-06 for the 1M Fable session = compact at ~50%; no hook can trigger compaction
metadata:
  type: reference
---

**Setting:** `~/.claude/settings.json` → `"autoCompactWindow": 500000` (added 2026-09-06 00:30 on Gene's "okay set it"). Schema: integer 100000–1000000. Also settable via env `CLAUDE_CODE_AUTO_COMPACT_WINDOW` or CLI `--autocompact 500k`. The session model is `claude-fable-5-1[1m]`, so 500000 ≈ half the window — Gene's standing "compact at ~50%" rule for `/myworkflow` loops.

**Facts verified 2026-09-05 (guide agent against code.claude.com docs):** no percentage knob exists; `PreCompact`/`PostCompact` hooks fire around a compaction already decided and cannot start one; `/compact` is user-initiated only; `/context` shows usage. UNVERIFIED: whether the window also applies to subagent contexts (opus Executors run 150–230k tokens each) — a reason not to go below ~300k.

**How to apply:** for other model windows scale to half (200K → 100000). Related: [[feedback_compact_at_50_percent_iteration_boundary]], [[feedback_iteration_close_print_remaining_tasks]].
