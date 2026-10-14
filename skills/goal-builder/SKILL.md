---
name: goal-builder
description: >
  Interview wizard that turns a rough intent into a well-formed /goal command: a verifiable
  completion condition plus a kickoff prompt with scope, evidence, and stop rules. Use when the
  user types /goal-builder, asks for help writing a goal prompt, wants to set up a long-running
  autonomous /goal session, or asks "keep working until X" and the condition is still vague.
---

# Goal Builder

Turn a vague "keep going until it's done" into a `/goal` condition a small checker model can
actually verify, plus a kickoff prompt that tells the agent how to work.

How `/goal` works (built-in, Claude Code ≥ 2.1.139): `/goal <condition>` sets a completion
condition. After each turn a small fast model reads the conversation and decides whether the
condition holds; if not, the agent starts another turn. **The checker only sees the transcript** —
so the condition must be provable from what the agent prints, not from external state.

## Step 1 — Interview

If the user supplied a rough goal as arguments, restate it and confirm. Then ask (batch the
questions; AskUserQuestion works well, plain questions also fine):

1. **Outcome** — What does "done" look like, concretely? Outcome, not activity.
2. **Proof** — What printed evidence demonstrates it? (pasted final test summary, build exit code,
   file listing, diff stat, URL responding 200). If they can't name proof, propose one.
3. **Scope** — Which repo/folder/files are in bounds? What must NOT be touched?
4. **Stop conditions** — What blockers should end the run early instead of thrashing?
   Max attempts on the same failure (default: 3, then report and stop)?
5. **Safety** — Any destructive operations allowed (delete, reset, drop DB)? Default: none.
   Standing rules still apply (e.g. commit only where the machine's git policy allows it).

Don't interrogate — one round of questions, sensible defaults for anything unanswered, note the
defaults in the output.

## Step 2 — Draft the goal condition

Rules for the condition line:

- **One sentence, outcome-stated.** "All unit tests in X pass" — never "work on the tests".
- **Transcript-provable.** Pair every claim with required evidence: "…and the final test-run
  summary is pasted showing 0 failed".
- **Escape hatch.** Append "or a blocker requiring user input has been clearly reported and work
  has stopped" so a genuinely stuck run completes instead of looping.
- **Quote-free.** No `"` or `'` inside the condition — quoting survives shells and hooks badly.
  Rephrase to avoid quoting anything.
- **Compound goals explicit.** Use "and" between sub-conditions; never rely on implication.

## Step 3 — Draft the kickoff prompt

A short prompt sent as the first message after `/goal`, containing: the task, scope boundaries,
the evidence to print when claiming completion, stop conditions with the retry cap, and the
safety constraints from the interview.

## Step 4 — Deliver

Output exactly this shape, then stop (do not run the goal yourself):

```text
/goal <the condition line>
```

```text
<kickoff prompt — paste as the next message>
```

Follow with a two-line note: which defaults were assumed, and a reminder that the checker model
only sees the transcript, so the agent must print the evidence the condition names.

## Anti-patterns

| Bad | Why | Better |
|---|---|---|
| Fix the failing tests | Activity, never provably done | All tests in TestAuto.Unit pass and the final summary shows 0 failed |
| Until the app works | Unverifiable from transcript | GET /health returns 200 and the response is pasted |
| Condition with nested quotes | Quote-mangling in hooks/shells | Rephrase quote-free |
| No stop rule | Infinite thrash on a hard blocker | 3 attempts per distinct failure, then report and stop |
