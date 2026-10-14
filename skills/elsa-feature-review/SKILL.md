---
name: elsa-feature-review
description: Periodic review of Elsa Workflows upstream — what's new in elsa-core releases, what ProFlow has adopted, and which features Speedmerchants vNext's W1/orchestration layer could use. Produces a dated report. Use when Gene says "check Elsa", "Elsa feature review", or during W1 planning.
---

# Elsa Feature Review

Purpose: Elsa is an active work-in-progress. vNext (Speedmerchants) plans to adopt it for the
orchestration plane (campaigns: prep-box → run-test → populate-DW), with ProFlow as the in-house
donor. This review keeps us current without anyone having to remember to look.

## Steps

1. **Upstream state** (WebSearch/WebFetch):
   - Latest release + notable recent releases: https://github.com/elsa-workflows/elsa-core/releases
   - Skim changes relevant to our use: child/sub-workflows, bookmarks/suspend-resume, SQL Server
     persistence, Elsa Studio (designer), versioning, distributed runtime, HTTP activities.
   - Check status of known issue **elsa-core#7397** (child-workflow resume in distributed
     environments) — it gates our composite-campaign design.
2. **ProFlow state** (read-only, `{ReposRoot}\proflow`):
   - Elsa package versions: `Directory.Packages.props` (or csproj `PackageReference`s in
     `Services.Proflow.Infrastructure`).
   - What integration surface grew since last review: `Services.Proflow.Infrastructure\Services\ElsaServices\`
     (new services/activities), `Testing\SampleWorkflows\`.
   - `git -C {ReposRoot}\proflow log --oneline -20` for recent direction.
3. **Our side**: read the W1/orchestration sections of
   `{VaultDocsRoot}\speed-merchants\planning\vNext_v2.md`
   (§11) and the ImplementationPlan's W1 item — compare capabilities we're waiting on.
4. **Report** to
   `{VaultDocsRoot}\speed-merchants\planning\ElsaFeatureReview_{yyyy-MM-dd}.md`:
   - Upstream: version delta since last review, features we could use now, #7397 status.
   - ProFlow: version pinned, new integration patterns worth lifting.
   - Recommendation: anything that changes W1's scope/timing (one paragraph, evidence-cited).
   - Keep it to one page. Link the previous review for the delta chain.

## Notes

- First review's baseline: 2026-08-29 — ProFlow on Elsa 3 (EF Core SqlServer, Http, Scheduling,
  Hangfire packages); vNext W1 not started; #7397 open.
- Read-only on both repos. Never bump vNext/ProFlow package versions from this skill — report only.

