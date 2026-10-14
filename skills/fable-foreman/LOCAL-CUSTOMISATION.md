# LOCAL CUSTOMISATION — quality-first routing policy

**Applied 2026-09-11 against upstream fable-foreman v0.5.0** (`fbfb032`,
https://github.com/olsenbrands/fable-foreman, MIT).

This file is **not upstream**. It exists because a `git pull` or a re-install copies the
upstream files over the top and silently reverts everything below. If you update this skill,
re-apply this policy and re-run the checks in "Verification" at the bottom.

Backups of every modified file, taken immediately before the edits:
`.backups/20260911-022449/`

---

## The policy

**2026-10-04 (owner):** every Fable seat moved to Opus (Opus 5.5 is better and cheaper). The lead runs on the session model (Opus) and the verifier seat is `model: opus`. Cheaper seats (`sonnet`, `haiku`) stay where the policy already uses them. The older lines below that mention Fable are history.

    OPUS      plan / architect / decompose / route (lead)
      ↓
    OPUS      primary implementation model
      ↓
    SONNET / HAIKU   only when clearly appropriate
      ↓
    OPUS      blind verification (fresh context)
      ↓
    repair if necessary
      ↓
    OPUS      final acceptance (lead)

**The one-sentence change:** upstream's First Law was *"cheapest model that clears the
quality bar"*. It is now *"use the strongest economically reasonable implementation model
by default, with Opus as the preferred code-writing worker; step down only when the task is
sufficiently mechanical or bounded that doing so is unlikely to reduce quality."*

The direction of the default is what moved. Upstream started at the bottom and climbed until
the bar was cleared; this starts at `opus` and steps *down* only on a positive, recorded
argument. **Cost alone is never that argument.**

## Files modified

| File | What changed |
|---|---|
| `SKILL.md` | First Law rewritten (quality-first). Class table re-cut: WORKHORSE→**IMPLEMENTATION (`opus`)**, new **BOUNDED (`sonnet`)**, FAST unchanged (`haiku`). Provider-preference block added. "Route to what is actually there" rows no longer make Grok the default bulk implementer; verifier seat named `opus`. Pre-approval clarified as authorization ≠ preference. Budget discipline: buy speed with parallelism, not a lower tier |
| `references/routing.md` | Claude seat map rewritten (`opus` = IMPLEMENTATION default). Dispatching `opus` workers declared ordinary, not an escalation. LEAD-must-not-implement rule + never-switch-Fable-to-save-money + disclose-if-Fable-unavailable. Step 2 inverted; 2a (record the step-down), 2b (effort ≠ licence to substitute sonnet for opus), 2c (pool asymmetry does not move implementation off Claude), 2d (parallelism buys speed) |
| `references/model-matrix.md` | Table 5 implementation rows re-cut to Opus-first, with a bounded row for Sonnet and FAST defaulting to Haiku. Preamble: price tables are evidence, not seat selection — First Law wins on conflict. Table 6 "Use:" no longer prefers off-family for bulk implementation |
| `references/delegation.md` | Added **The Claude repair ladder**: Opus→Opus repair→Fable re-verify; Sonnet failing on *reasoning* escalates to Opus on the first such failure; Haiku beyond mechanical escalates to Opus. Bounded-retry rules unchanged |
| `references/verification.md` | Verifier independence note updated: `model: opus` requested explicitly, not `inherit` |
| `references/grok-workers.md` | Grok 4.6 demoted from first-choice implementation seat to adversarial review + explicitly-requested alternative. The 2026-09-04 "use him for coding too" standing instruction is marked superseded for this installation. Grok support otherwise untouched |
| `../../agents/foreman-worker.md` | `model: sonnet` → **`model: opus`**; `effort: high` kept. "WORKHORSE" → "PRIMARY". Added the step-down contract: a `sonnet` override that turns out under-specified reports `NEEDS_CONTEXT` rather than pushing through |
| `../../agents/foreman-verifier.md` | `model: inherit` → `model: fable` (2026-09-11) → **`model: opus`** (2026-10-04); `effort: high` kept. Override is allowed but must be journaled; Opus unavailability is disclosed, never silently substituted |
| `../../agents/foreman-scout.md` | **Unchanged** — `model: haiku`, `effort: low`, as the policy requires |

## What was deliberately preserved

Delegation tickets · the ledger · worktree and write-set isolation · parallel dispatch ·
bounded retries and the precedence table · seat-provenance checks (Layer 0) · blind
verification · build/test verification · repair loops · lead final acceptance · the crew
performance record · **full Codex and Grok support**. None of these mechanisms was weakened;
only the routing *preference* changed.

No script was touched — no script hard-codes a Claude model or assumes Sonnet is the
workhorse (verified by grep across `scripts/*.sh`).

Nothing outside this skill and its five agents was modified: no `settings.json`, no hooks,
no permissions, no git controls, no worktree configuration, no unrelated skills or agents.

## Verification (re-run these after any upstream update)

```bash
cd ~/.claude/skills/fable-foreman
grep -rn "cheapest seat\|cheapest model\|default bulk implementation" . --include=*.md   # expect: no policy hits
grep -n "^model:" ../../agents/foreman-worker.md ../../agents/foreman-verifier.md ../../agents/foreman-scout.md
# expect: opus / opus / haiku
```

Expected frontmatter:

| Agent | model | effort |
|---|---|---|
| `foreman-worker` | `opus` | `high` |
| `foreman-verifier` | `opus` | `high` |
| `foreman-scout` | `haiku` | `low` |

## Known residual risk

**Per-dispatch overrides still outrank agent-file frontmatter.** That is the harness's
design and removing it would break legitimate routing (cross-family second opinions,
fallback when a seat is unavailable). The guard is procedural, not mechanical: the First Law
requires a recorded ledger rationale for any step-down below `opus` on code-writing work, so
a defeat of the Opus-first rule is *visible in the ledger* rather than prevented. A lead that
silently overrides to `sonnet` violates policy; nothing in the file system stops it.
