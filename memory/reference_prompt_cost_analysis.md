---
name: reference-prompt-cost-analysis
description: "Where Claude Code token cost actually goes — cache reads dominate; session length is the lever, not config size"
metadata: 
  node_type: memory
  type: reference
  originSessionId: d02b3e44-25af-4d0b-855f-2ee23d252231
  modified: 2026-08-01T16:46:37.710Z
---

Full analysis + automation plan: `C:\devopslocal\ObsidianVaults\Work\MyWorkVault\03 Shared\AICosts\ReducePromptCost.md`
(measured over 48h ending 2026-08-01; re-run the scripts in section 8 to refresh).

Durable findings — these are the counterintuitive ones worth not re-deriving:

- **Cache reads are 95% of tokens and 55% of cost.** The lever is `avg_context_per_turn`
  (= total cache-read / assistant turns), not the size of the config. Measured 225k/turn.
- **The always-loaded floor (~38k) is only 17% of an average turn.** Skills, MEMORY.md, and
  CLAUDE.md are NOT the problem — accumulated conversation history is. Trimming skills is a
  trigger-precision argument, not a token argument.
- **MCP tool schemas are deferred in Claude Code** — ~250 tools cost ~2.5k (names only), not
  ~125k. Generic "audit your MCP servers" advice does not apply here.
- **Cost scales ~quadratically with session length**, so `/clear` at task boundaries is worth
  more than every config change combined (~250M tok over 48h).
- **`Workflow` ≈ 36M tokens per run.** When the goal is just uninterrupted execution, a single
  `Agent` call gives the same property at ~1/3 the cost — and fixing the main loop (autonomy
  wording in CLAUDE.md) costs nothing and keeps steering. See [[feedback_workflow_parallelizes_agents]]
  and [[feedback_implement_autonomously]].
- Large tool results become **permanent context residents**. A `Write` to MEMORY.md echoes the
  whole file back (~13k tokens); use `Edit`. Prefer ranged `Read` over whole-file reads.

Health targets: avg context/turn under 120k; floor under 30k; denials under 5 per 48h.

Permission changes must be mirrored to `~/ai/permissions/permissions.yaml` — see [[reference_permissions_sync]].
