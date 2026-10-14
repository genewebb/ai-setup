---
name: dual-review-convergence
description: >
  Adversarial verification of a produced artifact using two context-isolated
  reviewers scored against one objective rubric, where both must pass before it
  ships, with a bounded fix-and-recheck loop using fresh reviewers each round.
  Includes a stratified batch-sampling mode for verifying large sets cheaply.
  Use when shipping something that will not get human review, when hallucination
  or omission risk is high, or when verifying a large batch where spot-checking
  would miss systematic defects.
---

# Dual-Review Convergence

Make a list, check it twice.

A single agent reviewing its own output shares the biases, knowledge gaps, and
systematic errors that produced it. Two independent reviewers with no shared
context break that failure mode.

## When to Use

- Output ships without human review
- Accuracy is load-bearing (technical docs, migration scripts, config that will
  run against a real environment)
- Hallucination risk is elevated (API references, version numbers, counts,
  claims about code that was not read)
- Batch generation where spot-checking misses systematic patterns

**Do not use** for internal drafts, exploration, or anything with deterministic
verification available. If a compiler, linter, or test suite can answer the
question, run that instead — it is cheaper and more reliable.

## Relationship to `llm-council`

These are not interchangeable. Choosing wrong wastes a lot of tokens.

| | `llm-council` | this skill |
|---|---|---|
| Question | "Which path should we take?" | "Is this artifact correct?" |
| Input | An open decision with several valid answers | A finished artifact + a fixed rubric |
| Voices | Deliberately different perspectives, expected to disagree | Identical rubric; disagreement is a defect signal |
| Output | A reasoned recommendation | PASS / FAIL plus specific blocking issues |
| Ends when | A choice is made | Both reviewers pass, or 3 rounds elapse |

Ambiguous decision → council. Finished artifact → this.

## Architecture

```text
GENERATE  ->  produce the artifact normally (this skill changes nothing here)
    |
    v
REVIEW    ->  Reviewer B  and  Reviewer C, in parallel
              - neither sees the other's assessment
              - identical rubric, identical inputs
              - structured verdict, not prose
    |
    v
GATE      ->  B passes AND C passes  -> SHIP
              otherwise               -> merge both issue lists -> FIX
    |
    v
FIX       ->  fix ONLY the flagged issues, then re-review with FRESH reviewers
              max 3 rounds, then escalate to the human
```

## Phase 1 — Generate

Unchanged. This is a post-generation verification layer, not a generation
strategy.

## Phase 2 — Dual independent review

Spawn two reviewers in parallel. Four invariants:

1. **Context isolation** — neither sees the other's assessment
2. **Identical rubric** — same criteria, same wording
3. **Same inputs** — both get the original spec *and* the artifact
4. **Structured verdict** — a typed result, not an essay

Each reviewer returns:

```json
{
  "verdict": "PASS | FAIL",
  "checks": [ { "criterion": "...", "result": "PASS|FAIL", "detail": "..." } ],
  "critical_issues": ["blockers that must be fixed"],
  "suggestions": ["non-blocking"]
}
```

Reviewer prompts must end with the adversarial framing:
**"Be rigorous. Your job is to find problems, not to approve."**
Without it, reviewers rubber-stamp.

## Rubric Design

The rubric is the most important input. Vague rubrics produce vague reviews.
Every criterion needs an objective pass condition.

| Criterion | Pass condition | Failure signal |
|---|---|---|
| Factual accuracy | Claims verifiable against source material | Invented statistics, wrong version numbers, nonexistent APIs |
| Hallucination-free | No fabricated entities, quotes, URLs, file paths | Links to nothing, cited files that do not exist |
| Completeness | Every requirement in the spec is addressed | Missing sections, skipped edge cases |
| Compliance | Passes project-specific constraints | Banned patterns used, conventions violated |
| Internal consistency | No contradictions within the output | Section A says X, section B says not-X |
| Technical correctness | Code compiles, logic is sound | Syntax errors, wrong complexity claims |

Domain extensions for this codebase:

- **Code** — null handling, error propagation (no silent failures), no secrets
  in source, parameterised SQL, tests for new paths
- **Docs and skills** — every cited file path exists; every referenced skill
  name exists; no bash where PowerShell is required
- **Migration or config that will execute** — idempotent, reversible, and the
  rollback is stated

## Phase 3 — The unanimity gate

```text
B == PASS and C == PASS  ->  SHIP
anything else            ->  merge and dedupe both issue lists  ->  FIX
```

**Both must pass. No partial credit.** If only one reviewer caught an issue, the
issue is still real — the other reviewer's blind spot is precisely the failure
mode this exists to eliminate. Never average the verdicts.

## Phase 4 — Bounded convergence loop

- Fix **only** the flagged critical issues. No refactoring, no unrequested
  improvements — those introduce new defects the reviewers have not seen.
- Re-review with **fresh reviewers** every round. A reviewer who saw the prior
  version anchors on it and stops looking.
- **Max 3 rounds**, then stop and escalate to the human with the outstanding
  issues. A loop that will not converge is information, not a failure.

## Batch Mode — stratified sampling

**The highest-value mode locally.** For a large set (a skill corpus, a failing
test suite, a batch of generated configs), full verification is prohibitive and
usually unnecessary, because defects in generated batches are *systematic*, not
random.

1. Sample 10–15% (minimum 5 items)
2. Run the full dual review on the sample
3. Classify every failure by **type**, not by item
4. If a type recurs, fix that **class** across the whole batch
5. Re-sample and re-verify
6. Repeat until a clean sample passes

Do not verify 140 items. Verify 15, find the systematic defect, fix the class,
re-sample. Fits `skill-fix-integration-tests` (categorise failures, fix the
category) and skill-corpus audits directly.

**Always report what was sampled and what was not.** A batch verified by
sampling must never be described as "verified" without that qualifier.

## Failure Modes

| Mode | Symptom | Mitigation |
|---|---|---|
| Infinite loop | New issues appear after every fix | 3-round cap, then escalate |
| Rubber stamping | Both reviewers pass everything | Adversarial framing; tighten the rubric |
| Subjective drift | Reviewers flag style preferences | Objective pass conditions only |
| Fix regression | Fixing A introduces B | Fresh reviewers each round catch it |
| Correlated blind spot | Both miss the same thing | Independence reduces but does not eliminate this. For critical output, add a third reviewer or a human spot-check. |
| Cost blowup | Long artifact, many rounds | Batch sampling; cap rounds |

## Cost

Roughly 2–3× the generation cost per verification cycle. Batch sampling cuts
that to ~15–20% of full verification while catching most systematic issues.
Worth it when the artifact ships unreviewed; wasteful when a test suite would
answer the same question.

## Related Skills

- `llm-council` — see the boundary table above
- `superpowers:verification-before-completion` — deterministic checks; run those
  first, this second
- `pr-review`, `/code-review` — human-in-the-loop review; if that is happening,
  this is usually redundant
- `skill-fix-integration-tests` — the natural consumer of batch mode

---

Adapted from ECC (MIT, © 2026 Affaan Mustafa) — <https://github.com/affaan-m/ECC>,
where this was published as `santa-method`.
