---
name: haiku-task-routing
description: >
  Routes low-complexity sub-tasks (searching text or files, reading long logs or reports, listing folders,
  minor text transforms, plain summaries and data extraction) to a Haiku sub-agent through the Agent tool
  with model "haiku", and keeps multi-file logic, debugging, design and irreversible changes in the main
  model. Use when a step needs a long read or broad search whose result can be returned as a short extract,
  for example a builder report, a gate review log, a suite log, or grepping many requirement files for one rule.
---

# Smart model task routing and Haiku handoff

## Objective

Save tokens and time by sending narrow, low-complexity sub-tasks to a Haiku sub-agent. Keep the main session
(Opus or Sonnet) for architecture, multi-file changes and deep logic.

Owner decision 2026-11-01: this skill is a deliberate exception to the CLAUDE.md Delegation rule ("prefer finishing
work in the main loop") for the task kinds listed under "Route to Haiku". Everything else still stays in the main loop.

## How to hand off

`/model claude-haiku-5-5` switches the WHOLE session's model; it is not a sub-agent. Hand off with the Agent tool
instead:

```
Agent(description: "<3-5 words>", model: "haiku", subagent_type: "general-purpose" (or "Explore" for read-only search),
      prompt: <the 4-part block below>)
```

A runner or subagent that has no Agent tool does the step itself.

## Route to Haiku

- Searching text or files.
- Reading and analysing logs, reports and review files longer than about 200 lines.
- Listing folders or inspecting directory structures.
- Minor text transformations, file renames or basic formatting updates in ONE file.
- Writing basic summaries or extracting data (ids, counts, file:line evidence).

## Keep in the main model

- Multi-file logic tracking and complex debugging.
- Core structural planning or system design, including any board, ticket or write-set decision.
- Irreversible changes (structural deletes, broad refactors, force operations, anything outward-facing).
- Any step whose exact output decides the next action and is already short (a script that prints one status line):
  running it directly is cheaper than briefing an agent.

## Execution pattern

1. Make the master plan for the request.
2. Mark the steps that qualify for Haiku.
3. Call the Haiku agent with a strict 4-part block:
   - TASK: the exact, narrow action.
   - INPUT: the file path(s) or the text snippet.
   - FORMAT: the exact return format (for example "one line per finding: id | file:line | one-sentence summary").
   - ESCALATION: "If the task needs multi-file context or you are unsure, output UNSURE immediately."
4. Merge the returned extract into the plan. On `UNSURE`, or when an id, count or path in the extract matters to a
   decision, verify it yourself before acting (read the cited line). Never act on an unverified Haiku claim for an
   irreversible step.
5. Independent Haiku reads go in one message so they run in parallel.

## Notes

- A Haiku agent starts with no context: put every path and id it needs in INPUT.
- Ask for verbatim quotes of ids, hashes and error lines; summaries drop them.
- Its output is not shown to the user; relay what matters.
