---
name: reference_factory_lambda_hides_missing_di_dependency
description: "A DI factory lambda is invisible to ValidateOnBuild, so a module test that supplies the missing dependency itself can hide a service that cannot resolve in any real host."
metadata: 
  node_type: memory
  type: reference
  originSessionId: 05a61cd5-462a-479d-b5d9-1ae50f21dcb5
  modified: 2026-09-20T13:58:35.261Z
---

`services.AddSingleton(p => new Foo(p.GetRequiredService<IBar>()))` validates clean even when
**nothing registers `IBar`**. `ValidateOnBuild` inspects constructor signatures; it cannot read
`GetRequiredService` calls inside a delegate it has not executed. The failure waits for whichever
request first resolves `Foo`.

The amplifier is the module's own composition test. It typically does:

```csharp
services.AddSingleton(TimeProvider.System);          // supplied BY THE TEST
services.AddSingleton<IAuthenticationAttemptStore>(...);
services.AddSpeedySecretProfiles(...);               // then the module
provider.GetRequiredService<RsaAssociationService>(); // passes
```

That proves the **module**, and never asks the **host** the question. Found twice in speedmerchants
on 2026-09-20 (Goal 4): `TimeProvider` and `IAuthenticationAttemptStore` were registered nowhere in
the composition root, so the entire Goal 2 Secrets profile family was unresolvable in every shipping
host while its tests passed.

**How to apply:** for each subsystem, add a test that resolves every registered service from the
*real* composition entry point (`AddSpeedy(configuration)` over a shipped sample), not from a
hand-built collection. Add a counterfactual that asserts the failure when the module is composed
alone, so the defect is pinned as real rather than described. A census that checks "is every
`AddSpeedy*` extension invoked" does **not** catch this — it catches a missing module, not a missing
dependency inside one, and catches nothing at all when no module exists yet.

Related: [[feedback_verify_no_guessing]], [[project_tech_stack]]
