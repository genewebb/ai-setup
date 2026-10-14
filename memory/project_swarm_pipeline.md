---
name: swarm-pipeline
description: Swarm agent pipeline architecture, handoff chain, and key behaviors
type: project
---

## Pipeline

Full pipeline: core-planner → constraint-reviewer → plan-integrator → decomposition-gate → plan-decomposer → [sub-plan-iterator ↔ sub-plan-checkpoint] → implementor → reviewer → tester → verifier

- **sub-plan-iterator** is a state machine (returns routingDecision to manager, does NOT invoke agents)
- **sub-plan-checkpoint** prompts user between sub-plans (continue/pause/stop)
- For decomposed runs: verifier loops back to sub-plan-iterator for next sub-plan evaluation
- Infrastructure agents (not in handoff chain): run-initializer, context-assembler, plan-validator, step-logger

Agent files live in:
- `c:\devops\repos\speed-merchants\.cursor\agents\` (working copy)
- `c:\devopslocal\repos\swarm\agents\` (adoption package — keep in sync)

## Key Behaviors Fixed

- **Decomposition gate** (`confirmDecompositionWithUser`): decomposition-gate agent must STOP with exact message showing `[1]`/`[2]`/`[3]` options before handing off to plan-decomposer. No defaults, no proceeding without explicit user response.
- **Sub-plan review checkpoint**: sub-plan-checkpoint agent prompts user with `[1]`/`[2]`/`[3]` (continue/pause/stop) between sub-plans. Manager dispatches via sub-plan-iterator routingDecision.
- **Checkpoint config**: reads `reviewCheckpoints.promptBetweenSubPlans` from `.swarm/config/plan-decomposer.json`.
- **stopped-by-user**: maps to run outcome `canceled` with `failure-reason: "stopped-by-user"` (not a separate outcome enum value).

## Config Locations

- `.swarm/config/construct-registry.json`
- `.swarm/config/rule-groups.json`
- `.swarm/config/workflow.json`
- `.swarm/config/plan-decomposer.json`
- `.swarm/config/tool-adapters/`
- `.swarm/policies.json`

## Scripts (swarm repo)

- `scripts/validate-swarm-config.ps1` — validates all config files
- `scripts/generate-tool-views.ps1` — generates CLAUDE.md, copilot-instructions.md, VSCode-GUIDELINES.md
