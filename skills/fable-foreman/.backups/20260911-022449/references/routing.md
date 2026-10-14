# Routing: resolving capability classes to live models

The skill's policy never names dated model IDs. This file is the procedure for resolving FRONTIER / WORKHORSE / FAST to what exists on the user's account **today**.

## The LEAD seat

The session model is the **LEAD seat** — it runs you, the foreman. Do not assume it is frontier-class: sessions start on mid-tier models, org fallbacks, and cost-capped configs. If FRONTIER-class judgment work is on the plan and you cannot establish that the LEAD seat is frontier-class (from the session's own model identity), say so and suggest the user switch models — routing architecture decisions to a mid-tier seat while calling it FRONTIER violates the First Law with extra steps.

**Frontier is a class, not a single model.** The test is whether the LEAD seat clears the frontier bar, never whether it is the *most* capable model in the lineup. Every current top-tier Claude family qualifies, and the foreman behaves identically in each: same classes, same gates, same tickets, same verification. A frontier LEAD must never recommend switching to a *different* frontier model — that is churn dressed up as rigor. Reserve the switch recommendation for a LEAD seat that is actually mid-tier or below.

**The seat can change under you.** Claude Code may move a session to a different model mid-run — safety-classifier fallback (which can also pin the session to the new model for its remainder), quota exhaustion, org policy, or the user typing `/model`. Treat the Step 0 probe as cache with an invalidation rule, not a one-time fact. On any signal the identity moved, re-probe and write one ledger line: `LEAD seat changed: <old class> → <new class> — <trigger>`. Then:

- **Frontier → frontier** (e.g. a fallback between top-tier families): nothing to re-plan. Finish the run; in-flight tickets stay valid, because tickets are written against classes.
- **Frontier → mid-tier** (a real downgrade): stop before the next FRONTIER-class dispatch, tell the user the seat dropped, and let them choose — restore the seat, re-route that work to a frontier subagent, or accept a documented reduction. This is a genuine run-level halt only if *everything* left is frontier-class work: park the frontier outcomes as `NEEDS USER` with the question and keep running the independent non-frontier work a surviving seat clears. Never quietly keep making frontier-class calls from a mid-tier seat.

**A mid-tier LEAD still accepts — but never on its own frontier-class judgment.**
The acceptance *act* is always the lead's, at every seat class: inspect the actual
candidate, reconcile the original requirements to the evidence, adjudicate the
consequential findings, personally check the critical behavior, and report incomplete
where a required observation cannot be made (verification.md, "Personal final
verification"). No reviewer's verdict is ever the acceptance decision, and a
frontier-qualified reviewer is not an exception to that.

What a mid-tier lead must not do is **substitute its own judgment for frontier-class
judgment on a frontier-class question** — an architecture call, an ambiguous defect,
a subtle correctness or security argument. On such a question it **obtains a
frontier-qualified seat's evidence** first: a pinned frontier verifier or frontier
subagent holding the original task verbatim, the candidate, and the evidence. The
lead then does the acceptance work against that evidence like any other. Where its
own reading would **disagree** with the frontier evidence, it neither overrides it
nor rubber-stamps it: **park the outcome** as `NEEDS USER` carrying both readings and
a concrete question, per the downgrade rule above, while independent work continues.

This is scoped to *frontier-class questions*: routine verifiers, scouts, and fix
reviewers do not all become frontier, and no provider family is excluded from
supplying the frontier-qualified seat when it is qualified.

## Claude seats

- **WORKHORSE** = the `sonnet` alias; **FAST** = the `haiku` alias. **FRONTIER** is normally the LEAD seat itself, but frontier-class *workers* are dispatchable too — the Agent tool's `model` parameter accepts frontier aliases (`opus`, `fable`) alongside `sonnet` and `haiku`. Aliases track the latest release in each family automatically — new releases require zero skill edits.
- **When to spend a frontier worker** (the First Law still applies — this is the expensive seat): genuinely independent frontier-judgment workstreams that must run in parallel; a blind verifier for a frontier-class change when no Codex counterpart exists; or a second opinion on a decision the run hinges on. Not for implementation a WORKHORSE clears. An Opus lead dispatching Opus workers is ordinary routing, not an escalation — but it is the priciest crew you can field, so announce it like any other fan-out.
- Pass the model per dispatch via the Agent tool's `model` parameter (overrides agent-file frontmatter). Treat it as a *request*: runtimes may substitute if the org disallows a tier. A dispatch behaving far above or below its class is a *trigger to check provenance* (verification.md Layer 0) — behavior is never itself the provenance mechanism, in either direction: anomalous output doesn't prove substitution, and normal-looking output doesn't prove the requested seat served.

- The built-in `Explore` agent inherits the session model — from any frontier LEAD that is an expensive default for background scanning, and when LEAD and `Explore` resolve to the same model you are paying frontier rates to grep. Dispatch `foreman-scout` (FAST) instead. (With Codex present, model-matrix.md prefers `gpt-5.6-luna` for FAST work; the bundled scout is haiku-pinned — use it for sub-minute recon where wrapper overhead would exceed the saving, and a luna Codex dispatch for large mechanical sweeps.)

### The silent-fallback hazard

A routing request the runtime can't honor may be **silently replaced, not rejected** — the dispatch proceeds on a different model with no error surfaced. Documented field case (claudemix, 2026-08): a non-Claude model string passed *inline* in an Agent tool call was silently dropped and the subagent ran on a Claude model, while the same string in the agent file's `model:` frontmatter routed correctly (through their proxy). The hazard generalizes: org policy denials, decommissioned aliases, and unsupported tiers can all land as silent substitutions.

Empirical status in Claude Code (tested 2026-08-07, current build): an agent file pinned to a foreign model **with no proxy present** fails *loudly* ("Agent terminated early due to an API error"), and inline `model` values outside the supported enum are rejected at schema validation — neither path silently substituted in our tests. Treat that as the harness's current behavior, not a guarantee: the substitution class remains real across runtimes, builds, and org policies.

Countermeasures, in order: **(1)** route non-standard models via agent-file frontmatter, never inline strings; **(2)** treat every `model` parameter as a request; **(3)** close the loop with Layer 0 seat provenance (verification.md) — deterministic evidence of the served model, which converts a silent substitution from an invisible routing error into a logged, handleable event.

## Seat evidence is disclosed, not gating

Four provenance facts are recorded **separately** for every dispatch, and none is a
substitute for another (verification.md Layer 0 defines the tiers):

- **requested** — the model and effort you asked for (`-m`, `model:`, an effort flag).
- **billed** — the model a provider's own accounting names for the turn.
- **routed** — evidence of the path a request took without naming the served model.
- **served** — an artifact produced *after* model resolution naming the model that answered.

Record each on the attempt line with its type, and write `unavailable` where the
surface does not expose it. **A missing serving field is uncertainty, not a
violation:** the seat is logged `seat: unverified` and the acceptance that rests on
it discloses that tier. Disclosure is the whole consequence — an unevidenced seat is
not disqualified from a role it is otherwise qualified for (SKILL.md hard rail 6).
The requirement that a dispatch ran on the *exact* requested identity simply stays
**unproved** without served evidence; do not claim it, and do not infer it from
output quality in either direction.

**A detected substitution is a route fault**, not a ticket failure: evidence showing a
different seat than routed invalidates the seat mapping. Repair the route or change
transport before re-dispatching, and count a repeated substitution on the same route
as a real failure toward the precedence table (delegation.md) — never loop free
retries into a route known to lie.

## Effort — use the controls that actually exist

Effort is a real dial, but only where a mechanism exists to set it. Per surface:

- **Codex workers**: set it explicitly per invocation — `-c model_reasoning_effort=<level>` (see codex-workers.md).
- **Claude subagents**: the bundled role files carry static defaults — scout `low`, worker `high`, verifier `high` — so a FAST scout never silently inherits an expensive session effort. These are starting points, not fixed levels: where your harness offers a per-invocation effort control, **the lead's per-dispatch choice overrides the file default**; if a model/effort combination isn't supported, the runtime falls back to the model's default — log what actually applied. Where no control exists, don't pretend: convey expected depth in the ticket ("mechanical batch edit; do not deliberate" / "reason carefully about the concurrency implications").
- Heuristics: low/minimal for mechanical work; provider default for normal work; deep effort only for hard verification and design. Raising effort on a cheap seat is often better economics than raising the tier — try it first for borderline tasks (precedence table row 2).

**Effort is chosen per dispatch by the lead, deliberately, from the levels that
actually exist.** No table, role file, or pre-approval fixes it. The choice is made
against the task's shape and risk, the seat's payoff curve (model-matrix.md Table 4),
and the performance record; **discretion exists only where the model and the
transport both support the control** — where they do not, the effort is the model's
default and the ticket carries the intended depth in words instead. For **Grok**,
where no evidence exists for a seat on this kind of work, the **no-evidence prior is
the highest effort that Grok seat supports**. Other providers retain the task-driven
heuristics above and their model defaults where no runtime control exists. The record,
once it has comparable outcomes, overrides the Grok prior in either direction. Log the
effort you requested and the effort that actually applied — they differ when a
combination is unsupported.

### Route hypothesis and the performance record

**Write a route hypothesis before every dispatch**, one ledger line: the seat, the
effort, and *what you expect it to buy* — the observation that would keep the choice
and the observation that would overturn it (e.g. "grok-4.6, high — expect first
artifact inside 20 min and no re-rank of severities; overturned by a second failed
fix wave"). After the outcome, record keep-or-change with the observation that
settled it. A route decision with no hypothesis is untestable and teaches the record
nothing.

**Before a comparable dispatch, read the relevant slice of the global performance
record** (`~/.foreman/crew-performance.md`; schema and append contract in
delegation.md) — same role, task shape, and risk class, not the whole file. It is the
evidence behind seat and effort choices, and it refuses to conclude what it cannot
support: no universal provider rankings, no accuracy without a denominator, no served
identity from self-report or billing, no "fast first completion" read as lower
whole-delivery cost. Sparse or uncontrolled samples are context, never a causal
saving.

## Codex seats

Follow codex-workers.md: probe → consent → **discover the account's actual tiers** (config.toml preference, `/model`, or asking the user; documentation ≠ entitlement; IDs differ by auth mode) → verify each tier you intend to use with one tiny call → map verified tiers to classes by the provider's published positioning → record the mapping in the ledger (consent is skipped only when the probe reports the user's opt-in pre-approval — codex-workers.md).

Providers commonly ship flagship / workhorse / economy tiers, but treat that as a pattern to check, not an invariant. The user's configured default model is their *preference* — identify what it is before classifying it; a user who pinned the flagship as default did not thereby make the flagship your WORKHORSE.

> **Dated example — not policy.** As of 2026-07 the Codex flagship family was GPT-5.6: Sol (flagship), Terra (positioned "everyday workhorse"), Luna ("clear repeatable tasks"), with ChatGPT-account logins using suffixed IDs (`gpt-5.6-sol`) where API-key auth used bare ones (`gpt-5.6`). By the time you read this, assume the lineup has changed — run the discovery procedure.

## Grok seats

Follow [grok-workers.md](grok-workers.md): probe → note billing mode → tiers are
fixed and small (`grok-4.6` default, `grok-4.5`) → dispatch only through
`scripts/grok-dispatch.sh`.

- **Grok 4.6** — first-choice **implementation** seat (bulk WORKHORSE and hard FRONTIER tickets) and first-choice **adversarial-review** seat under the user's pre-approval (SKILL.md Step 0 item 5), **effort chosen by the lead per dispatch** (see "Effort" above; the no-evidence prior is the highest level this seat supports). Its review verdict is scoped evidence for the lead, like any reviewer's — acceptance stays with the lead (verification.md). Up to the pre-approval's parallel ceiling (default 15, a reported successful concurrency default, not a measured maximum) with disjoint write sets.
- **Grok 4.5** — lower-capability fallback. Launcher-validated fact, not a policy: `grok-4.5` has no `xhigh` level — sending it exits 1, so "highest supported" for this seat is the level below.
- **The 200K cliff is a routing boundary, not a surcharge to absorb.** Grok
  reprices the *whole* request 2x above 200K — a jump that is certain from xAI's
  published policy. Which alternative then wins on cost is **not** established
  (Table 3): the comparison is list-price math, and measured Grok billing on a
  subscription ran far under list. Route away from the surcharge; do not assert a
  specific cheaper seat as fact. Above 500K Grok is ineligible outright. Apply it
  reactively, not by pre-counting tokens: the launcher reports the dispatch's
  average prompt size per model call and emits `CONTEXT WARN`/`CONTEXT ALERT`.
  **Reactive rule:** after a `CONTEXT ALERT`, do not send Grok another ticket
  that carries the *same context set or a superset* (same working files/paths
  plus the same or a longer resumed session) — that is a fact the foreman knows
  from what it put in the ticket. A fresh ticket with a smaller context set may
  still use Grok; when unsure, don't. A `CONTEXT WARN` means shrink the next
  ticket's context or split it. See model-matrix.md Table 3.
- Grok auto-discovers the user's Claude Code config (CLAUDE.md, skills, agents,
  MCP servers, hooks) by default. The launcher switches that discovery off at
  the source (`GROK_CLAUDE_*_ENABLED=false`) and pins the remaining
  countermeasures; never hand-compose a `grok` command that skips them. Grok
  still prepends its own system prompt and toolset (~19K tokens on this build
  with discovery off; ~28K with the user's Claude config discovered).

## Choosing the seat for a task

0. **Consult [model-matrix.md](model-matrix.md)** — the evidence table for price, capability, context limits, effort payoff, and task-type placement. This procedure decides *which class*; that table decides *which seat within it*, and records what each choice actually costs.
1. Classify the task's *judgment content*, not its size. A 500-line mechanical rename is FAST; a 10-line concurrency fix is FRONTIER.
2. Apply the First Law: cheapest seat that clearly clears the bar; unsure → one seat up.
2b. **Effort before tier.** The payoff curve depends on task shape, not difficulty: analysis/review is nearly flat (medium ≈ high at 70-85% of cost), long-horizon coding is steep. Raising effort costs ~20%; raising a tier costs 2-5x. See model-matrix.md Table 4.
2c. **Claude workers drain the same allowance the foreman runs on**; Codex and Grok workers do not. For bulk implementation, prefer an off-family seat so the run itself lasts longer. This never licenses a seat that fails the task's bar — remaining allowance is not observable on any provider, so nothing here allocates quota.
3. **Claude vs Codex vs Grok within a class — qualification, then preference.** A seat is eligible when it clears the task's bar on all of: **capability** for this task shape; the **tools and transport** the ticket actually needs (a reviewer with no shell cannot run the checks — verification.md); the **task's risk** if it goes wrong; **availability** (quota, auth, rate limits, context ceiling); the **user's stated preference**; **relevant performance history** from the global record for comparable work; and **total delivery cost through acceptance**, not the first dispatch's price. No provider family is excluded from a role by family alone; prefer cross-family pairing for build/verify, and prefer the provider under less quota pressure among qualified seats.
4. **Read the record's relevant slice, then write the route hypothesis** ("Route hypothesis and the performance record" above) before dispatching.
5. Log every routing decision in one ledger line: `task → class → seat (+effort requested / effort applied) — why`, and record the seat-evidence tier when the dispatch returns.

## Currency rule

If anything suggests your model knowledge is stale — an unfamiliar name from the user, an alias resolving oddly, an entitlement error on dispatch — verify against live provider docs or the account itself before routing. This repo's own first Codex dispatch failed on exactly this: a day-old model family, a CLI predating it, and an auth-mode ID split no static document had caught yet.
