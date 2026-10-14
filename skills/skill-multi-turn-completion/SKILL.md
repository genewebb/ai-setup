---
name: skill-multi-turn-completion
description: >
  Patterns for long-running skills that span multiple model turns: disk-first batching,
  resume-from-file checkpoints, micro-batch accounting, and step boundary persistence.
  Use when building skills requiring 100+ MCP calls, model-driven data validation,
  step-by-step verification workflows, or any skill where context loss mid-run must
  not require restarting from scratch.
---

Repo: speed-merchants (paths below are repo-relative)

# Multi-Turn Skill Completion

> **Source**: `SkillModelAndDataReview.md` — the canonical implementation of this pattern
> **Problem it solves**: Skills that need hundreds of MCP calls cannot complete in one model turn. Without disk checkpoints, any context reset means starting over.

---

## When to Use

- Processing N entities/records where N > ~20 (MCP calls × 2 sides = context pressure fast)
- Any skill with "Step 1 → Step 2 → Step 3 → Summary" structure
- Work that may resume across multiple chat sessions
- Skills where partial completion is worse than no completion (produce a complete report, not a fragment)

**Do NOT use** for simple one-shot operations that fit in a single turn.

---

## Core Principle: The File Is the System of Record

**Do not rely on model memory or conversation context for progress state.**
After every micro-batch, write progress to disk. The next turn opens the file and continues — no "please say continue" handoffs.

---

## The Four Patterns

### 1. Disk-First Batching

Write to the report file **before** emitting lengthy natural-language summaries.

```
For each micro-batch:
  1. Call MCP tools (Local + Remote)
  2. Compare/diff results
  3. WRITE to report file (mismatch tables + progress JSON)
  4. Then summarize in chat (brief)
```

**Never**: accumulate results in memory across multiple batches and write once at the end.

### 2. Micro-Batch Sizing

| Context pressure | Recommended batch size |
|---|---|
| Stable / plenty of headroom | 25 items per logical batch |
| Moderate (most runs) | 5-10 items per assistant message |
| MCP transport unstable | 3-5 items; pause between messages |

Track progress with two levels:
- **Logical batch** (e.g. 25): for human-readable progress logging
- **Micro-batch** (e.g. 5-10): the actual flush boundary (what gets written to disk between turns)

### 3. Resume-From-File Checkpoints

Every disk write must include a machine-readable state block:

```json
{
  "step3_entities_required_count": 96,
  "step3_entities_compared_count": 40,
  "step3_last_compared_entity": "CustomerAddress",
  "step3_next_entity_to_compare": "CustomerContact",
  "step3_complete": false,
  "run_status": "in_progress"
}
```

**Resume protocol** (start of any turn after a pause):
1. Open the dated report file
2. Parse the Step N state block
3. Resume from `step3_next_entity_to_compare` (or equivalent)
4. Never reset `entities_compared_count` backward

### 4. Step Boundary Persistence

Between major steps (Step 2 → Step 3 → Step 4 → Summary), **read the file before proceeding** — not from memory of prior tool output.

```
Step 2 ends  → write Step 2 JSON handoff block → read file → begin Step 3
Step 3 ends  → confirm step3_complete: true → read file → begin Step 4
Step 4 ends  → read full file → write Executive Summary
```

---

## State Block Schema

### Step 3 (attribute/item comparison)

```json
{
  "step3_entities_required_count": 96,
  "step3_entities_compared_count": 0,
  "step3_last_compared_entity": "",
  "step3_next_entity_to_compare": "EntityA",
  "step3_complete": false,
  "run_status": "in_progress"
}
```

Optional failure fields: `"step3_failure_reason"`, `"step3_failed_entity"`.

### Step 4 (counts/tallies)

```json
{
  "step4_entities_required_count": 96,
  "step4_entities_compared_count": 0,
  "step4_next_entity": "EntityA",
  "step4_complete": false
}
```

---

## Forbidden Handoff Patterns

| Forbidden | Use instead |
|---|---|
| "Say 'continue' to resume" | Write `step3_next_entity_to_compare` to disk; next turn reads it |
| "I'll stop here, come back later" | Write checkpoint, continue in next turn automatically |
| Claiming completion when `step3_complete: false` | Label as "paused" or "in progress" |
| Resetting count backward on context loss | Re-read the file; only re-fetch the current micro-batch if the last write may have failed |

---

## Turn Boundary Handling

**If a turn ends mid-Step 3** (token/tool budget hit after a successful file write):
- State is `run_status: "paused"`, `step3_complete: false`, `step3_next_entity_to_compare` set
- Next turn: open same file → read state → continue from `step3_next_entity_to_compare`
- This is a **resumable pause**, not a failure

**If context is lost** (new chat, model reset):
- Re-read the full report file
- Parse Step 2 and Step 3 JSON blocks
- Resume from `step3_next_entity_to_compare` — do not re-compare already-counted entities

---

## Completion Criteria

A run is **complete** only when ALL of these are true:
1. `step3_entities_compared_count == step3_entities_required_count`
2. `step3_complete: true` in the JSON block
3. Step 4 has run (if applicable)
4. Executive Summary is written (reflecting full body, not a stub)

---

## Applied Example: SkillModelAndDataReview

The canonical implementation. Originally triggered by an `AGENTS.md` rule (that file was removed 2026-05-31 — for Claude Code this skill triggers via its description; OpenCode/Copilot regenerate their own `AGENTS.md`):

> For documented multi-turn skills (notably **SkillModelAndDataReview**), drive the **same dated report file** to the skill's success criteria... Use **disk-first micro-batching**... Work **may span multiple model turns**; the next turn **reads that file** and continues.

Report path: `{VaultDocsRoot}\speed-merchants\ModelAndDataReview_{yyyy-MM-dd}.md`
- `speedMcpLocal` = Source
- `speedMcpRemote` = Target
- DateTime/Date `data_type_information` 0↔250 = noise, do not report as mismatch

---

## Anti-Patterns to Avoid

- In-memory state accumulation across turns
- Assuming context survives between assistant messages
- Writing a summary before completing all batches
- Stopping mid-Step 3 without a disk-persisted resume pointer
- Using `get_all_attributes` bulk API instead of per-entity calls (for SkillModelAndDataReview)

---

## Sources

- `{VaultDocsRoot}\speed-merchants\Archive\SkillModelAndDataReview.md`
- `AGENTS.md` (multi-turn skill rule, lines 17-18) — *source removed 2026-05-31; this skill is now canonical*
