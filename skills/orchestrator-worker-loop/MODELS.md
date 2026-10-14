# Model Tier Reference

The skill and prompt templates refer to abstract model **tiers**. This file maps tiers to concrete
model slugs per AI CLI. Update when your tool adds or renames models.

## Tier definitions

| Tier | Purpose | Selection rule |
|---|---|---|
| **reasoning** | Judgment-heavy work: Orchestrator planning, Verifier decisions, novel problem-solving | The most capable reasoning model your CLI exposes |
| **balanced** | Multi-file coordinated edits, typed refactors, moderate reasoning | Mid-tier model that understands cross-file context |
| **fast** | Mechanical work: regex substitution, formatting, straightforward file edits | Cheapest tier that reliably follows structured prompts |

## Claude Code (this CLI)

The subagent-dispatch tool's `model` parameter accepts exactly these values:

| Tier | Slug |
|---|---|
| reasoning | `opus` |
| balanced | `sonnet` |
| fast | `haiku` |

Notes specific to this CLI:

- **Omitting `model` inherits the session model.** That is usually the reasoning tier, which
  defeats the entire cost argument for the Executor — so set it explicitly on every dispatch.
- **Owner ruling 2026-10-04: no Fable seats.** The SESSION (Orchestrator: planning, PLAN + grader authoring) and the
  Verifier (six gates, proof re-runs) run on `opus` (Opus 5.5, better and cheaper than Fable); every Executor
  dispatch is `model: opus`. Start the session with `claude --model opus`.
  (Before this ruling, from 2026-09-06, the session ran on `fable`.)
- The auto-upgrade ladder is therefore: `haiku` -> `sonnet` -> `opus`.
- Reasoning effort can be set per dispatch where the tool exposes it. Prefer a higher effort for the
  Orchestrator/Verifier and the default for a mechanical Executor.

## Other tools

### Cursor-style explicit slugs

| Tier | Slug |
|---|---|
| reasoning | `claude-opus-5-thinking-high` |
| balanced | `claude-sonnet-5-thinking-high` |
| fast | `composer-2.5-fast` |

### OpenAI-family

| Tier | Slug |
|---|---|
| reasoning | `gpt-5-high` (or your CLI's highest reasoning slug) |
| balanced | `gpt-5-medium` |
| fast | `gpt-5-mini` (or `gpt-4o-mini`) |

### Add your own

Append a subsection when running in a tool not covered above. The skill only needs the slug to pass
to whatever subagent-dispatch mechanism the CLI exposes.

## Default assignments used by the skill

Unless GOAL.md overrides:

| Role | Default |
|---|---|
| Orchestrator | reasoning |
| Executor | fast (auto-upgrade one tier per consecutive failure, for that iteration only) |
| Verifier | same session as the Orchestrator (no separate dispatch) |

## Rough cost-per-token proxy (order-of-magnitude only)

Concrete pricing varies by tool. Rough ratios for intuition:

| Comparison | Ratio (output tokens, dominant cost) |
|---|---|
| reasoning vs fast | 30-100x more expensive |
| balanced vs fast | 3-10x more expensive |
| reasoning vs balanced | 5-15x more expensive |

Reasoning-tier models also emit far more output (thinking) tokens, so the observed differential is
larger than the price differential alone implies.

## Measured calibration — one real run

Numbers from a single instrumented run, so treat them as an order-of-magnitude anchor rather than a
benchmark. Shape: a 14-site feature in a large, heavily-tested .NET solution, Orchestrator and Verifier
on `opus` in-session, Executor on `sonnet`.

| Metric | Value |
|---|---|
| Executor dispatches | 8 (7 iterations, one retry) |
| Executor subagent tokens | **644,463** total, ~80k median per dispatch |
| Range per dispatch | 60,217 (a one-line fix) – 139,768 (two new test classes) |
| Wall clock | 1h11m for 7 iterations |
| Regression cost | ~31s per run (2,673 tests), run 2x per iteration |

### The dispatch floor, and what follows from it

A well-scoped Executor dispatch with an explicit file list costs **60-140k tokens regardless of how
small the edit is**. The floor is reading the precedent files — the one-line fix still cost ~60k, because
the Executor still had to read enough to know what the line should say. Edit size barely moves it.

Two consequences:

- **Batch trivial follow-ups into a neighbouring iteration** rather than giving each its own dispatch.
  Three one-line fixes as three dispatches cost ~180k; folded into one iteration they cost ~70k, because
  the reading is shared.
- **Do not dispatch at all for a genuinely mechanical one-token edit** where the Verifier's own gates
  are the real check. Paying 60k to delegate a change you can make and verify directly is pure loss.

This cuts against the instinct that smaller actions are always safer. Smaller actions are safer for
*correctness* (tighter constraint gate, clearer success criterion) and worse for *cost* — and below a
certain edit size the correctness benefit is nil because there is nothing to get wrong. Split for risk,
batch for triviality.

## Cost visibility — read this before setting a dollar cap

**Dollar caps are advisory. Nothing in this skill enforces them.** Claude Code does not expose
per-subagent dollar cost to a running skill, and most other CLIs do not either. `Test-Budget.ps1`
therefore enforces only what it can measure:

- iterations (from PROGRESS entries)
- wall-clock (from `state.json.started_at`)
- consecutive failures
- consecutive no-change iterations (thrash)

Set `max-iterations` and `max-duration` to values you would actually accept paying for, and treat
`max-cost-usd` as a note to yourself rather than a guardrail. Where the CLI does surface token or
cost figures, log them in the PROGRESS entry so the final report can total them.
