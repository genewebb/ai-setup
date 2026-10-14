---
name: requirements-implementation-goal
description: >-
  Turns a requirements area into a Claude /goal command and detailed implementation handoff with pinned
  definitions, dependency scope, acceptance traceability, evidence and blocker rules. Use when releasing
  requirements to a coding agent or drafting a requirements-based implementation goal. Produces a clearly
  blocked draft when decisions or approvals are missing. Does not implement the application or start the goal.
---

# Requirements Implementation Goal

Prepare a goal another coding session can finish and prove while requirement authors continue other areas. Produce the full context as a file and a short goal that loads it before work. Writing a prompt does not authorize running it.

The user's preparation command is `/definegoal`, for example `/definegoal Secrets`. Its thin router is `{AIWorkRoot}\commands\definegoal.md`. This skill generates instructions for the existing native `/goal`; it never replaces that command or runs it during preparation.

## Establish authority and scope

Use the user's selected area, order, repositories, output location, approvals and execution boundaries. Infer them from the current task before asking. Ask only for consequential missing information; continue independent preparation. Do not repeat settled product choices.

For Speedy, read [references/speedy-context.md](references/speedy-context.md) and its live authoring authority. For another project, obtain the corresponding requirements and approval method. Do not transplant Speedy's paths, IDs, roles, product decisions or current work order into another project.

The requirements-writing skill owns authoring and applying answers; this skill owns implementation handoffs. Its absence does not remove the authoritative standard. The shared goal-builder skill can clarify an unknown finish line; it does not require another interview when the task already supplies one.

Read the selected artifacts, actual statuses, questions, decisions, authors, reviews and approvals. Distinguish donor observations, inclusion candidates, target obligations, implementation observations and executed evidence. Follow binding applicability/prerequisite/refinement links transitively. In Speedy, referencing an individual REQ makes its whole owning artifact a definition prerequisite; related links, capability membership and candidate mappings add no such edge.

Check runtime integration separately: a complete definition graph does not prove identity, hosting, storage or consumer boundaries exist. Include necessary shared contracts without pulling the whole application into the first release. Donor application areas are coverage packages, not a reason to implement a shared feature twice. If a shared artifact blocks unrelated consumers, propose a genuinely independent split through authoring; never narrow a link or ignore a question to evade readiness.

## Classify and preserve the baseline

- **Draft, not released:** unresolved decisions, answers pending application, missing scope, stale hashes, absent approval or unavailable pinned contents. Produce the useful prompt and precise readiness list while keeping implementation gated. Continue authorable work.
- **Ready to start:** the actual project gates and review/approval hold for the selected definitions and prerequisite revisions, and all handoff inputs are retrievable. Report the supporting evidence. Do not add an approval ceremony or ask again for approval already recorded for those revisions.

Run supported definition validation, then distinguish it from human gates. A pass does not supply missing approval, source support or acceptance coverage. A same-tool new context or goal evaluator is not independent review where the standard forbids it.

Preserve the issued contents in a retrievable snapshot outside live artifact discovery. Record normative hashes for approval identity and file hashes for snapshot integrity; they are different. Do not invent a repository commit for an uncommitted vault. Reference actual approvals rather than creating a second approval system in a manifest. Read [references/release-record.md](references/release-record.md) when constructing the companion record.

## Choose one goal or a staged sequence

Use one goal for a cohesive, manageable outcome. Use multiple goals when a large package has meaningful, independently verifiable implementation checkpoints or dependency stages. The full handoff stays in files in either case; the 4,000-character command limit is not a reason to fragment requirements arbitrarily.

For a staged sequence, produce a short numbered plan and a separate full prompt and length-checked `/goal` command for each stage. Name its outcome, prerequisite stages and evidence, assigned REQ/AC/VERIFY IDs, concrete completion checks, and work it leaves for later stages. Assign every released requirement an accountable implementation stage; explicitly map cross-cutting acceptance and verification so nothing falls between stages or is counted complete twice. Never invent the allocation from feature titles without reading the obligations. An early goal may finish its assigned subset while the containing feature's implementation remains incomplete; report that boundary plainly.

Keep one approved release baseline across the sequence. Dividing implementation work does not split or weaken a whole-artifact approval, change a requirement, or require repeated approval of unchanged definitions. Order goals by real dependencies and preserve usable integration points between them. Parallel execution requires actual authorization and non-overlapping ownership; preparing multiple goals does not launch agents or replace an active goal.

Finish with an explicit integration and release-verification goal. It reconciles the entire approved REQ/AC/VERIFY index, checks the composed user and execution paths, and establishes evidence applicable to the final implementation. Reuse valid earlier evidence where appropriate and rerun checks affected by later changes. Several completed component goals do not establish complete product acceptance. Present each command separately with its character count and prerequisite checkpoint; start only when instructed.

## Write the full implementation prompt

Adapt [assets/implementation-prompt.md](assets/implementation-prompt.md). Preserve the outcome, verified baseline, scope, gap assessment, implementation, verification, parallel-work, checkpoints and final-evidence sections. Replace all markers in an issued prompt. Missing inputs may remain only in a conspicuously labelled draft.

Make the packet self-contained for a new session, referencing actual normative sources instead of duplicating every requirement and old decision. Include exact source/release/checkout locators, complete REQ/AC/VERIFY traceability, meaningful exclusions, supported implementation observations, and real execution authority.

Require the implementer to retain conforming existing work, integrate actual UI/CLI/host/consumer paths, and report requirement gaps instead of editing acceptance to fit code. Evidence must expose incorrect behavior and appear in the transcript: actual commands/exits, criterion coverage, failed/not-run cases, implementation revision/dirty-state identity and evidence locations.

Carry the task's permissions forward. Do not infer commits, deployments, messages, orchestration or delegation from permission to prepare a prompt. Do not add confirmations for routine implementation already authorized. Use a proportionate retry/escalation rule; three materially different unsuccessful attempts is a suggested default, not a universal product requirement.

## Form the goal and launch instructions

Claude's native `/goal` starts a turn immediately. Put the complete prompt in a readable file first, and have the goal tell Claude to read that exact file and its release record before code changes. Alternatively preload all context before setting the goal. Never tell the user to send essential constraints after starting a bare goal.

**Goal command length: at most 4,000 characters.** Gene supplied this client limit on 2026-09-19. Apply it to the complete text the user will paste, including `/goal`, spaces, paths and any newlines. Keep the full implementation handoff in its referenced file; the command contains only the loader, outcome and essential completion/blocker condition. Do not paste the full handoff into `/goal` or truncate requirements to fit.

Before delivery, count the exact final command with a tool, not by estimation. Use a conservative UTF-16 code-unit count (JavaScript `text.length`, or Python `len(text.encode("utf-16-le")) // 2`); for ordinary ASCII commands this is the character count. Include the `/goal` prefix even if a client excludes it, but exclude Markdown fences and explanatory text. If the count exceeds 4,000, shorten the command or move detail into the full prompt, preserve the exact verified file locator and essential outcome, and count again. Prefer one short line with ample room below the limit. Report `N/4,000 characters` outside the copy/paste code block.

Use a concise, outcome-based condition with visible proof, preferably one sentence without nested quotes. Substitute real values in this example:

```text
/goal Read <absolute full-prompt path> first and follow its verified release and scope; implement the complete <area/release> and print reconciled REQ and AC coverage plus actual passing build and required verification evidence, or report a concrete external blocker with affected IDs and remaining work and stop without claiming implementation complete.
```

The blocker clause prevents thrashing; it does not make the product finished. The final report must distinguish **IMPLEMENTED AND VERIFIED** from **BLOCKED / INCOMPLETE**, even if the goal mechanism regards the escape condition as satisfied. Mere difficulty, consumed time or unfinished work is not an external blocker.

Use syntax supported by the receiving client; check its help or official documentation if uncertain. [Claude goal documentation](https://code.claude.com/docs/en/goal), checked 2026-09-19, establishes immediate start, evaluation from surfaced conversation evidence, and unchanged tool permissions. Keep reasoning/model selection with the user; `/ultra` in this Speedy task was their reasoning choice, not an integration to install.

Do not launch or replace a goal, create a task, or change client configuration merely to deliver this packet.

## Parallel work and publication

The implementer reads the released snapshot. The requirements coordinator drafts later areas or proposed revisions without overwriting it. Adopting changed contracts needs applicable impact review and approval. Unrelated drafts do not rewrite the historical baseline; an actual defect affecting it still needs disposition.

Keep requirements and application writes under separate owners. When multiple implementers are authorized, assign isolated checkouts and a shared-file integration owner; also isolate conflicting ports, data and tests. This preparation skill does not itself spawn workers.

Before publication, reread inputs and reconcile concurrent edits. Verify references, binding pins, review/approval identity, traceability counts and source availability. Inspect the packet for missing markers, fallback to newer drafts, unsupported commands, fake evidence or unstated permissions. Local checking is not independent certification.

Write through the authorized channel and verify exact readback. Speedy vault and shared-skill writes use Obsidian. Never embed credentials. Deliver the length-checked goal command with its measured character count, full prompt link, release/readiness record link and concise readiness state. A draft says what remains; an issued packet must not make the receiving agent invent missing inputs. Stop after preparation unless execution was separately requested.
