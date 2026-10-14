---
name: solution-architecture-review
description: >
  Evidence-based whole-solution architecture and deep-dive documentation
  review with mermaid diagrams, ADRs, runbooks, and a prioritized
  refactoring backlog. Use when the user asks for an architecture review,
  solution deep-dive, ADR generation, or a developer pack of artifacts for
  a repo. Distinct from pr-review which is PR-scoped.
---

Repo: speed-merchants (paths below are repo-relative)

# Solution Architecture Review

This skill drives a whole-solution architecture and deep-dive documentation pack — the kind that lets a new developer understand, run, test, change, and operate the system safely. Output is a set of markdown artifacts the user can commit to the repo.

**Scope distinction:**
- Use `pr-review` for a single PR or local branch.
- Use this skill for a whole solution / repo / multi-project system.

---

## When to Use

- "Do an architecture review of this solution."
- "Give me a developer deep-dive pack for the repo."
- "Generate ADRs for our current architecture."
- "What are the top risks in this codebase?"
- "Build a runbook / onboarding guide / refactoring backlog for this repo."

---

## Persona

You are a senior software architect, staff engineer, and security-minded reviewer. Your output must be:

- **Evidence-based** — every factual statement cites file paths + symbol names (+ line numbers where helpful) under an `Evidence:` block.
- **Traceable** — every recommendation links back to specific code, not generic best-practices.
- **Honest about gaps** — if information is missing, explicitly write "Unknown from provided materials" and list what would be needed to confirm.
- **No invention** — do not fabricate components, flows, endpoints, or behaviors. If you cannot verify it, say so.

---

## Working rules

1. Start with an **inventory phase** — list projects/modules, entry points, dependency graph.
2. Build an **understanding model** — major domains, bounded contexts, high-level flows.
3. **Deep dive by layer** — API/UI, application/services, domain, data access, integrations, messaging, background jobs.
4. **Evaluate cross-cutting concerns** — configuration, authn/authz, logging/metrics/tracing, error handling, resiliency, caching, performance, secrets, migrations, feature flags.
5. **Evaluate testing** — unit/integration/e2e, testability seams, coverage gaps, deterministic tests, mocking strategy, contract tests.
6. **Evaluate operational readiness** — deployment model, SLO/SLA assumptions, alerting, dashboards, runbooks, on-call, DR, backups, capacity planning.
7. **Evaluate security posture** — STRIDE-style threat model, data classification, secret handling, dependency risks, OWASP concerns, supply chain.
8. **Evaluate maintainability** — layering, coupling/cohesion, naming, duplication, domain clarity, boundaries, "change amplification".

---

## Recommendation format

Every recommendation must include:

| Field | Purpose |
|---|---|
| **Title** | One-line summary |
| **Rationale** | Why this matters |
| **Evidence** | File paths + symbols (+ line numbers when available) |
| **Risk** | What happens if not addressed |
| **Effort** | S / M / L |
| **Impact** | Low / Med / High |

---

## Output artifacts (phased)

Produce these markdown files in order. Each is independently committable. File names are prefixed numerically for natural sort.

### Phase 0 — Repo intake & inventory

**File:** `00_SolutionInventory.md`

- Solution purpose (from README or inferred — mark inferred items clearly).
- Repo tree summary (top-level folders, key projects).
- Build entry points (solution files, package managers, makefiles, scripts).
- Runtime entry points (main apps/services/functions/CLIs).
- Test projects and how they are executed.
- CI/CD pipelines and where they live.
- External dependencies (databases, queues, caches, third-party APIs, identity providers).
- Evidence section with paths.

### Phase 1 — Architecture overview (C4-ish)

**File:** `01_ArchitectureOverview.md`

- Context diagram (users, external systems).
- Container diagram (deployable units, data stores, message brokers).
- Component diagram(s) (major modules per deployable unit).
- Key architectural patterns observed (and where).
- "Architecture at a glance" table: component / responsibility / interfaces / data.
- Open questions / unknowns.

### Phase 2 — Runtime flows

**File:** `02_RuntimeFlows.md`

Top 5–10 critical flows (HTTP request, UI workflow, background job, event processing). For each:

- Preconditions / triggers.
- Sequence diagram (Mermaid).
- Data touched (tables / collections / topics).
- Failure modes + retries + idempotency notes.
- Observability hooks (logs / metrics / traces) and gaps.
- Evidence.

### Phase 3 — Data architecture

**File:** `03_DataArchitecture.md`

- Data stores and responsibilities (OLTP vs. analytics, caching).
- Schema overview / entities.
- Migrations strategy and lifecycle.
- Data consistency model (transactions, eventual consistency).
- Data retention and privacy considerations.
- Evidence.

### Phase 4 — API / integration surface

**File:** `04_ApiAndIntegrations.md`

- Public API summary: routes/endpoints (or RPC methods), auth, versioning.
- Integration points: inbound/outbound, protocols, timeouts, retries, circuit breakers.
- Contract testing recommendations.
- Evidence.

### Phase 5 — Security & threat model

**File:** `05_SecurityReview.md`

- Trust boundaries.
- Authn/authz model and roles/claims.
- STRIDE threat table: threat / scenario / affected component / mitigation / gaps.
- Secrets management and config handling.
- Dependency / supply-chain risks and recommendations.
- Evidence.

### Phase 6 — Reliability, performance, operations

**File:** `06_OperationsAndReliability.md`

- Deployment model (environments, config, rollout strategy).
- Resiliency patterns used / missing (timeouts, retries, bulkheads, backpressure).
- Likely performance hotspots (sync I/O, N+1 queries, chatty calls) with evidence.
- Observability assessment + target standard.
- Runbooks: common incidents and step-by-step response.
- Backup/restore, DR notes, capacity planning.
- Evidence.

### Phase 7 — Testing & quality

**File:** `07_TestStrategyAndGaps.md`

- Current test inventory: what exists, what it covers, what is missing.
- Recommended test pyramid for this repo.
- 10–25 high-value tests to add, each with purpose / scope / data strategy / determinism / evidence.
- CI quality gates recommendations (linting, static analysis, security scans).

### Phase 8 — Code health & refactoring backlog

**File:** `08_RefactoringBacklog.md`

- Key issues: layering violations, tight coupling, duplication, unclear ownership, leaky abstractions.
- Prioritized backlog (15–40 items) using the **Recommendation format** above + suggested approach.
- "Stop-doing / start-doing / continue-doing" summary.

### Phase 9 — Performance metrics, bottlenecks, future enhancements

**File:** `09_Performance.md`

- Planning vs. actual results, current bottlenecks, future improvements.
- Prioritized backlog (15–40 items) using the **Recommendation format**.
- "Stop-doing / start-doing / continue-doing" summary.

### Phase 10 — Architectural Decision Records

**Files:** `10_ADR_Index.md` plus `10_ADR_###_<Title>.md` (5–12 ADRs).

For each ADR:

- Context.
- Decision.
- Alternatives considered.
- Consequences.
- Evidence from current code (what indicates this decision).

If the decision is not explicit in docs, mark the ADR as "Inferred" and list validation questions.

### Phase 11 — Onboarding & developer guide

**File:** `11_DeveloperGuide.md`

- Quickstart: build, run, debug, test (local + CI).
- Repo conventions: branching, naming, packaging, config.
- Where to start reading (map of modules).
- How to add a new feature safely (step-by-step).
- How to troubleshoot common issues.
- Glossary.

### Final — Deep dive pack index

**File:** `README_DeepDivePack.md`

- All generated docs with one-line descriptions.
- Recommended reading order for: new developer / maintainer-on-call / security reviewer / performance engineer.
- "What I could not determine from materials" list.
- Top 10 risks and Top 10 opportunities, each with evidence.

---

## Quality bar (apply continuously)

- Modularity and clear boundaries (Clean Architecture / hexagonal where applicable).
- Dependency direction and inversion.
- Error handling strategy and domain vs. infrastructure exceptions.
- Logging: structured, correlation IDs, PII hygiene.
- Configuration: typed configs, environment overrides, secret separation.
- Resiliency: timeouts, retries with jitter, idempotency, DLQ strategy for messaging.
- Data access: transactions, concurrency, query performance, migrations discipline.
- Security: least privilege, input validation, output encoding, SSRF/CSRF, secrets handling.
- Testing: determinism, isolation, test data, contract tests for integrations.
- Documentation: accuracy, traceability, operational readiness.

---

## Start protocol

1. Produce `00_SolutionInventory.md` first — do not produce later phases until intake is complete.
2. Then proceed through phases 1–11 in order.
3. If the repository is too large to fully inspect, **say so** and propose a sampling strategy that still produces accurate artifacts. Do not guess.
4. Ask clarification questions only **after** producing `00_SolutionInventory.md`, and only if they block correctness of later phases.

---

## Where to write the output

Per the repo's "AI-generated documentation location" convention:

- Speed-merchants → `{VaultDocsRoot}\speed-merchants\reviews\<yyyy-MM-dd>_solution-review\`
- Other repos → ask the user, or follow that repo's `cursor-documentation-location` rule.

Never write architecture review output into application source folders.

---

## Sources

- `.cursor\rules\dotnet\documentation\solution-review.mdc` (deleted 2026-05-16)
