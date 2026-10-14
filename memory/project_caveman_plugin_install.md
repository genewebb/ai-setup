---
name: project_caveman_plugin_install
description: "caveman plugin install failed with EPERM rename — transient AV lock, retry fixed it; installer fallback double-wires hooks"
metadata: 
  node_type: memory
  type: project
  originSessionId: 53a58b71-1c48-49a4-95ea-f3001a30dc42
  modified: 2026-08-01T20:43:01.952Z
---

Installed caveman (JuliusBrussee/caveman) on 2026-08-01. Three gotchas:

1. `claude plugin install` failed: `EPERM: operation not permitted, rename '…cache\temp_local_…' -> '…cache\caveman\caveman\<sha>'`. **Not a rights problem** — the same `Directory.Move` succeeded by hand seconds later. Transient Windows handle lock (AV/indexer) on a large freshly-copied tree; Node reports it as EPERM, not EBUSY. The staged temp copy was also *incomplete* (missing `.claude-plugin/`, `agents/`, `commands/`, `dist/`).
   **Fix:** delete the partial `cache\<marketplace>\<plugin>` dir + the stale `cache\temp_local_*`, then re-run `claude plugin install <plugin>@<marketplace>`. Marketplace clone under `plugins\marketplaces\` is separate and usually fine.

2. Its `install.ps1` falls back to **standalone hook wiring in `~/.claude/settings.json`** when the plugin install fails. If you then fix the plugin install, SessionStart/UserPromptSubmit hooks fire **twice** (~300 extra tokens/session + duplicate reminder per prompt). Kept the plugin copy, stripped the settings.json entries (backup: `settings.json.bak-2026-08-01-cavemandedup`). Orphan `.js` files remain in `~/.claude/hooks\caveman-*` — unwired, harmless.

3. The `npx skills add … -a cursor/github-copilot` legs write to **`.\.agents\skills` relative to cwd**, not a global location. Run from `C:\Tmp` → skills landed in `C:\Tmp\.agents\skills`, useless. Re-run inside the target repo (with `--all`/`--with-init`) if Cursor/Copilot coverage is wanted.

Relates to [[reference_prompt_cost_analysis]], [[reference_claude_hook_activation]].
