---
name: crewchief-nested-workloads
description: >
  RunWorkloadStep — running a workload inside a workload in CrewChief. Covers the three-layer parameter
  precedence and the merge that has ALREADY happened before the executor runs, the Func<IWorkloadEngine>
  factory that exists only to break a DI construction cycle, by-name child resolution through
  IWorkloadResolver, the depth-first reference-cycle detector, and the transfer warning that a workload
  does not carry its children. Use when authoring or debugging a nested workload, working on
  RunWorkloadExecutor / IWorkloadResolver / NullWorkloadResolver / WorkloadResolver, diagnosing doubled or
  missing parameters in a child, a container that fails to construct, or a transferred workload whose
  children are absent.
---

Repo: speed-merchants (paths below are repo-relative)

# Nested workloads — `RunWorkloadStep`

A workload can run another workload as a step. Two of its mechanics are counter-intuitive enough that the
natural implementation is wrong, and one of them breaks container construction rather than a run.

## When to Use

- "Run workload B as a step inside workload A"
- "The child sees the parameter twice" / "the child does not see my parameter"
- "The container fails to construct after I simplified the executor"
- "I transferred the workload and the children are missing"
- "Does a self-reference get caught?"

## 1. Parameter precedence — and the merge already happened

Layering is **parent < child < child-step**: a child's globals beat the parent's globals, and a child
step's own parameter beats both.

**The trap:** each merge is applied **EXACTLY ONCE, by a different layer.** The parent-globals-into-step
merge has *already* been done by `UtilityOrchestrator` **before any executor runs** — so by the time
`RunWorkloadExecutor` executes, **the executor's own `Parameters` ARE the parent globals.**

Re-merging them inside the executor is the natural mistake and it doubles the layer. Take
`Parameters` as already-merged and layer only the child's own values over it.

## 2. `Func<IWorkloadEngine>`, not `IWorkloadEngine` — and do not "simplify" it

The executor takes a **factory**, purely to break a DI construction cycle:

```
orchestrator → RunWorkloadExecutor → engine → orchestrator
```

Injecting `IWorkloadEngine` directly closes that loop and **the container fails to construct** — not at
run time, at startup. A new developer tidying away "an unnecessary factory" breaks the whole host. The
factory is load-bearing; the comment at `RunWorkloadExecutor.cs:20-41` says so.

## 3. The child is resolved BY NAME, at execution time

`IWorkloadResolver` looks the child up **by name when the step runs** (`WorkloadResolver` →
`IWorkloadFileStore.Get`, ordinal). That makes nesting **rename-FRAGILE, not rename-tolerant**: rename or
delete a child and every parent's `RunWorkloadStep.workloadName` now names nothing, and the parent fails at
its next run — not when the change is made.

The guard lives in **`WorkloadReferences`** (`CrewChief.Data/Services/WorkloadReferences.cs`), the ONE reader
of `RunWorkloadStep` references: `RunWorkloadTargets(steps)` (accepts the `RunWorkloadStep`/`RunWorkload`
aliases, skips blank names), `FindParents(workloads, child)` (includes a self-reference) and
`RewriteReferences(parent, old, new)` (rewrites only `workloadName`, keeping a hand-edited property
spelling). The Workloads page lists parents in the Rename dialog and rewrites + saves them after
`WorkloadFileStore.Rename` (each parent re-read fresh; a self-referencing parent re-read under its NEW
name), and names them in both delete confirms. `WorkloadTransferService.FindWorkloadReferences` delegates to
`RunWorkloadTargets`, so the export warning and the rename can never disagree about what counts.
The CLI has no workload rename, so nothing there needs the rewrite.

`NullWorkloadResolver` is the **no-nesting default** for hosts that do not wire a store. It is a named
type rather than a null so a host without nesting still gets a definite "no such child" answer instead of
a null-reference. Same reasoning as `NoPublicationCentrals` elsewhere in the estate: an absent collaborator
answers the question, it does not decline it.

## 4. The cycle detector stops where the blame stops

`FindWorkloadReferenceCycle` is a depth-first walk over nested references:

- A **direct self-reference is a 1-hop cycle** and is caught.
- It **deliberately stops at unresolvable grandchildren** rather than reporting them as *this* step's
  failure. A child that names a workload nobody can resolve is that child's problem to report, not a cycle.

That second point is a deliberate scoping of blame, not an incomplete traversal.

## 5. Transfer does not carry children

A transferred workload references its children **by name**, so exporting a parent does **not** bundle
them. There is a transfer-time warning for exactly this, and
`RunWorkloadTransferWarningTests` pins it. See [[crewchief-workload-transfer]].

Run As inheritance also flows through nesting — see
[[crewchief-adding-a-step-type]] for the `WorkloadRunAsInheritance` rules.

## A stale comment to ignore

`IWorkloadResolver.cs:10-16` still says *"the concrete implementation … is written and registered
elsewhere, at the composition root, in a LATER iteration. Nothing in this project constructs or registers
an implementation of this interface."* That is **no longer true** — `WorkloadResolver` and
`NullWorkloadResolver` both exist and are wired in `EngineServiceCollectionExtensions.cs` and
`CrewChief.Web/Program.cs`. `RunWorkloadExecutor.cs:39-40` carries the same outdated "out of scope for this
iteration" note about the factory, which is also wired.

## Sources

- `CrewChief\CrewChief.Engine\Executors\RunWorkloadExecutor.cs`
- `CrewChief\CrewChief.Engine\Steps\RunWorkloadStep.cs`
- `CrewChief\CrewChief.Engine\Orchestration\IWorkloadResolver.cs`
- `CrewChief\CrewChief.Engine\Orchestration\NullWorkloadResolver.cs`
- `CrewChief\CrewChief.Data\Services\WorkloadResolver.cs`
- `CrewChief\CrewChief.Tests.Unit\Data\RunWorkloadTransferWarningTests.cs`
- `CrewChief\CrewChief.Web\Documentation\51_StepGuideRunWorkload.md`
