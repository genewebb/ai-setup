---
name: dotnet-documentation
description: >
  XML doc and code documentation standards. Use when writing /// summary tags,
  adding remarks or param documentation, creating class-level docs, reviewing
  code comment standards, or deciding what to document in C# code.
---

# Class and Code Documentation Rules

## Purpose

Use a short, consistent "class header" comment to make code reviews faster and higher quality by answering:

- What this class does (and does **not** do)
- Why it exists (context / problem statement)
- How it fits into the architecture (boundary and collaborators)
- How to use it correctly (invariants, lifecycle, concurrency)
- What can go wrong (failure modes, errors, retries)
- What matters for maintainability (extensibility, testing, performance, security)

This is not a change log and should not restate the implementation line-by-line.

---

## Recommended Format (C# XML Doc)

Use `/// <summary>` for a one-liner and `/// <remarks>` for structured detail. Keep headings stable so readers know where to look.

```csharp
/// <summary>
/// <One sentence: the responsibility and boundary of this class>.
/// </summary>
/// <remarks>
/// <para><b>Context</b>: Why this exists and where it sits in the architecture.</para>
/// <para><b>Responsibilities</b>:</para>
/// <list type="bullet">
///   <item><description>Primary responsibility #1</description></item>
///   <item><description>Primary responsibility #2</description></item>
/// </list>
/// <para><b>Non-goals</b>: Explicitly out of scope behaviors.</para>
/// <para><b>Key invariants</b>:</para>
/// <list type="bullet">
///   <item><description>Assumption that must always hold</description></item>
/// </list>
/// <para><b>Lifecycle &amp; concurrency</b>: Thread-safety, caching, disposal, idempotency.</para>
/// <para><b>Dependencies</b>: External systems and assumptions about them.</para>
/// <para><b>Error handling</b>: What is handled vs surfaced; retries/backoff; failure modes.</para>
/// <para><b>Performance notes</b>: Hot paths, IO patterns, batching, caching expectations.</para>
/// <para><b>Security</b>: AuthN/AuthZ expectations, PII handling, logging redaction.</para>
/// <para><b>Extensibility</b>: How to extend safely (new provider/strategy/etc.).</para>
/// <para><b>Testing</b>: Unit vs integration expectations; key seams.</para>
/// <para><b>Usage</b>: Minimal example if non-obvious.</para>
/// </remarks>
public sealed class ExampleClass
{
}
```

---

## Required Sections (Minimum Standard)

These should appear for **most** production classes:

1. **Summary**
   - 1 sentence: what the class is responsible for and its boundary.

2. **Context**
   - Why it exists; what problem it solves; where it sits in the architecture.

3. **Responsibilities**
   - 2-6 bullets; prefer outcomes over mechanisms.

4. **Non-goals**
   - 1-4 bullets; prevents scope creep and clarifies boundaries.

5. **Key invariants**
   - Assumptions that must always be true (ordering, nullability, identity, idempotency, state, etc.).

6. **Lifecycle & concurrency**
   - Thread-safety expectation (thread-safe / not thread-safe / confined).
   - Caching behavior (if any).
   - Disposal, resource ownership, reentrancy.

7. **Error handling**
   - What exceptions can be thrown.
   - What failures are retried vs surfaced.
   - What is logged and at what level.

8. **Testing**
   - What must be unit-tested.
   - What must be integration-tested (and why).
   - How to mock/fake primary dependencies.

---

## Conditional Sections (Include When Applicable)

Add these when relevant to the class:

- **Dependencies**
  - External services, API clients, database, message bus, file system.
  - Timeouts and SLAs if important.

- **Performance notes**
  - Hot path designation.
  - Expected volume (records/s, requests/min).
  - IO patterns (N+1 risks, batching).
  - Memory pressure / allocation concerns.

- **Security**
  - How tokens/credentials are obtained and protected.
  - PII classification and redaction rules.
  - Authorization expectations and boundary.

- **Extensibility**
  - How to add a new implementation (provider, handler, strategy).
  - Registration mechanism (DI, factory, convention).
  - Compatibility constraints (interface stability, versioning).

- **Usage**
  - Include a minimal usage snippet if correct usage is non-obvious or ordering matters.

---

## Style Rules

- **Be explicit about boundaries.** "This class orchestrates X; it does not validate Y."
- **Write in outcomes.** Prefer "publishes provider sync events" over "calls PublishAsync."
- **Document invariants, not trivia.** Avoid repeating method names unless non-obvious.
- **Do not maintain a change log here.** Use PRs, commit history, and ADRs for that.
- **Keep it scannable.** Paragraphs short; prefer bullet lists.
- **Use stable wording.** Reviewers should quickly find: Context, Non-goals, Invariants.

---

## Length Guidance

| Class Type | Typical Lines |
|------------|---------------|
| Simple utility / helper | 5-10 |
| Typical business class | 10-25 |
| Architectural seam (provider/orchestrator/cache) | 30-60 |
| Complex service with many responsibilities | 40-80 |

If documentation exceeds 80 lines, consider:
- Moving detail to an ADR or design doc and linking to it
- Splitting the class into smaller, focused components

---

## Documentation by File Type

### Interfaces (`I*.cs`)

Full documentation. The interface is the contract; document it thoroughly.

```csharp
/// <summary>
/// Defines the contract for governance metadata provider operations.
/// </summary>
/// <remarks>
/// <para><b>Context</b>: Abstraction layer allowing multiple provider implementations (Purview, Alation).</para>
/// <para><b>Implementations</b>:</para>
/// <list type="bullet">
///   <item><description><see cref="PurviewGovernanceProvider"/> - Microsoft Purview integration</description></item>
///   <item><description><see cref="AlationGovernanceProvider"/> - Alation Data Catalog integration</description></item>
/// </list>
/// <para><b>Key invariants</b>: All methods are async and support cancellation.</para>
/// </remarks>
/// <seealso cref="IGovernanceProviderFactory"/>
public interface IGovernanceProvider { }
```

### Abstract Base Classes

Full documentation. Include guidance for implementers.

```csharp
/// <summary>
/// Base class for all MDM message handlers, providing common logging and error handling.
/// </summary>
/// <remarks>
/// <para><b>Context</b>: Reduces boilerplate in NServiceBus message handlers.</para>
/// <para><b>For Implementers</b>:</para>
/// <list type="bullet">
///   <item><description>Override <c>HandleCoreAsync</c> for business logic</description></item>
///   <item><description>Do NOT override <c>Handle</c> directly</description></item>
/// </list>
/// </remarks>
public abstract class MdmMessageHandlerBase<T> { }
```

### Static Helper Classes

Full documentation. Helpers are often widely used; good docs prevent misuse.

```csharp
/// <summary>
/// Centralized cache key formatting and parsing for all cache operations.
/// </summary>
/// <remarks>
/// <para><b>Context</b>: Ensures consistent cache key structure across all providers and cache layers.</para>
/// <para><b>Key Patterns</b>:</para>
/// <list type="bullet">
///   <item><description>MDM: <c>mdm:{type}:{format}:{value}</c></description></item>
///   <item><description>Alation: <c>alation:{url}:{type}:{id}</c></description></item>
///   <item><description>Purview: <c>purview:{url}:{type}:{id}</c></description></item>
/// </list>
/// <para><b>Thread-safety</b>: All methods are pure functions; fully thread-safe.</para>
/// </remarks>
public static class CacheKeyFormatter { }
```

### Concrete Classes

Full documentation per the standard template.

### Test Classes (`*Tests.cs`)

Full documentation. Focus on test coverage and setup requirements.

```csharp
/// <summary>
/// Unit tests for <see cref="AlationGovernanceProvider"/>.
/// </summary>
/// <remarks>
/// <para><b>Test Coverage</b>:</para>
/// <list type="bullet">
///   <item><description>Provider capabilities and configuration</description></item>
///   <item><description>Entity/attribute cache operations</description></item>
///   <item><description>Sync state tracking</description></item>
/// </list>
/// <para><b>Dependencies</b>: Uses <see cref="MockAlationClient"/> for API isolation.</para>
/// <para><b>Category</b>: Unit tests - no external dependencies required.</para>
/// </remarks>
[TestClass]
[TestCategory("Unit")]
public class AlationGovernanceProviderTests { }
```

---

## Special Class Types

### Partial Classes

When a class is split across multiple files:

- **Main file** (`ClassName.cs`): Full class-level documentation
- **Partial files** (`ClassName.*.cs`): File-level comment explaining the subset of functionality

```csharp
// GovernanceService.cs (main file)
/// <summary>
/// Core service for managing MDM metadata synchronization with governance providers.
/// </summary>
/// <remarks>
/// <para><b>Context</b>: Central orchestration point for all governance operations.</para>
/// <!-- Full documentation here -->
/// </remarks>
public partial class GovernanceService { }

// GovernanceService.Delete.cs (partial file)
/// <summary>
/// GovernanceService - Delete Operations.
/// Contains methods for deleting MDM artifacts from the governance provider.
/// </summary>
/// <remarks>
/// <para><b>Methods in this file</b>: DeleteMdmEntitiesAsync, DeleteMdmAttributesAsync, etc.</para>
/// <para><b>See main class</b>: <see cref="GovernanceService"/> for full documentation.</para>
/// </remarks>
public partial class GovernanceService { }
```

### NServiceBus Message Handlers

For `IHandleMessages<T>` implementations, include handler-specific sections:

```csharp
/// <summary>
/// Handles <see cref="MdmEntitiesAdded"/> messages when new entities are created in MDM.
/// </summary>
/// <remarks>
/// <para><b>Message</b>: <see cref="MdmEntitiesAdded"/></para>
/// <para><b>Trigger</b>: Published by MDM Platform when entities are created.</para>
/// <para><b>Processing</b>:</para>
/// <list type="bullet">
///   <item><description>Creates entities in governance provider (Purview/Alation)</description></item>
///   <item><description>Updates IMdmMetadataCache with new entity data</description></item>
/// </list>
/// <para><b>Idempotency</b>: Yes - uses upsert semantics; safe to replay.</para>
/// <para><b>Error handling</b>: Failures are logged and message is retried per NServiceBus policy.</para>
/// </remarks>
public class MdmEntitiesAddedHandler : IHandleMessages<MdmEntitiesAdded> { }
```

### Cache Miss Handlers

For cache population handlers:

```csharp
/// <summary>
/// Handles cache miss events for Alation provider keys.
/// </summary>
/// <remarks>
/// <para><b>Key Prefix</b>: <c>alation:*</c></para>
/// <para><b>Processing</b>:</para>
/// <list type="bullet">
///   <item><description>Parses cache key to extract entity/attribute ID</description></item>
///   <item><description>Calls <see cref="IGovernanceProvider"/> to fetch data from Alation API</description></item>
///   <item><description>Writes result to cache via <see cref="IDistributedCache"/></description></item>
/// </list>
/// <para><b>Storm Protection</b>: Integrates with miss-in-progress markers and negative caching.</para>
/// </remarks>
public class AlationCacheMissHandler : IHandleMessages<CacheMissEvent> { }
```

### Provider Implementations

For `IGovernanceProvider` implementations:

```csharp
/// <summary>
/// Alation implementation of the governance provider interface.
/// </summary>
/// <remarks>
/// <para><b>Provider</b>: Alation Data Catalog</para>
/// <para><b>API Client</b>: <see cref="IAlationClient"/></para>
/// <para><b>Capabilities</b>:</para>
/// <list type="bullet">
///   <item><description>SupportsBulkCacheLoad: false (uses cache-miss pattern)</description></item>
///   <item><description>SupportsGranularDelete: false (requires model drop-and-resync)</description></item>
///   <item><description>RequiresSyncStateTracking: true</description></item>
/// </list>
/// <para><b>Stub Methods</b>: Relationship/Hierarchy/MatchingStrategy operations return success (unsupported by Alation).</para>
/// </remarks>
/// <seealso cref="IGovernanceProvider"/>
/// <seealso cref="PurviewGovernanceProvider"/>
public class AlationGovernanceProvider : IGovernanceProvider { }
```

### Controllers

For ASP.NET Core controllers:

```csharp
/// <summary>
/// API endpoints for MDM entity governance operations.
/// </summary>
/// <remarks>
/// <para><b>Route</b>: <c>/api/v{version}/entities</c></para>
/// <para><b>Authentication</b>: Requires API key via <c>x-api-key</c> header.</para>
/// <para><b>Endpoints</b>:</para>
/// <list type="bullet">
///   <item><description>GET /{id} - Fetch entity governance properties</description></item>
///   <item><description>GET /{id}/attributes - Fetch entity's attribute list</description></item>
/// </list>
/// </remarks>
[ApiController]
[Route("api/v{version:apiVersion}/entities")]
public class EntitiesController : BaseController { }
```

### Extension Methods

For static extension method classes:

```csharp
/// <summary>
/// Extension methods for <see cref="IDistributedCache"/> adding JSON serialization support.
/// </summary>
/// <remarks>
/// <para><b>Serialization</b>: Uses Newtonsoft.Json with error handling for computed properties.</para>
/// <para><b>Thread-safety</b>: All methods are thread-safe (stateless).</para>
/// </remarks>
public static class DistributedCacheJsonExtensions { }
```

---

## Abbreviated Documentation (Models/DTOs/Records)

For simple data transfer objects and record types, use abbreviated documentation:

**Include only:**
- **Summary**: One sentence describing the data this represents
- **Property documentation**: Only for non-obvious properties

**Skip:** Context, Responsibilities, Non-goals, Testing, Lifecycle, etc.

```csharp
/// <summary>
/// Represents the result of a delete detection operation during synchronization.
/// </summary>
public class DeleteDetectionResult
{
    /// <summary>
    /// Indicates whether any deletions were detected.
    /// </summary>
    public bool DeletesDetected { get; set; }

    /// <summary>
    /// The number of deleted items detected.
    /// </summary>
    public int DeleteCount { get; set; }

    /// <summary>
    /// Indicates whether a full resync is required due to detected deletions.
    /// </summary>
    public bool RequiresResync { get; set; }
}
```

### Enum Types

Abbreviated documentation. Document individual values if non-obvious.

```csharp
/// <summary>
/// Defines the operational status of the Governance service.
/// </summary>
public enum ServiceStatus
{
    /// <summary>Service is not configured (missing required settings).</summary>
    Unconfigured,
    
    /// <summary>Service is initializing and configuring providers.</summary>
    Configuring,
    
    /// <summary>Service is loading cache from provider.</summary>
    CacheLoading,
    
    /// <summary>Service is fully operational and ready to handle requests.</summary>
    Ready
}
```

### Constants Classes

Abbreviated documentation. Group related constants logically.

```csharp
/// <summary>
/// Cache key prefix and format constants used by <see cref="CacheKeyFormatter"/>.
/// </summary>
public static class CacheKeyConstants
{
    /// <summary>Prefix for MDM metadata keys.</summary>
    public const string MdmPrefix = "mdm";
    
    /// <summary>Prefix for Alation provider keys.</summary>
    public const string AlationPrefix = "alation";
}
```

---

## Cross-References

Use `<seealso cref="..."/>` to link related types:

| Relationship | Example |
|--------------|---------|
| Interface -> Implementation | `<seealso cref="PurviewGovernanceProvider"/>` |
| Implementation -> Interface | `<seealso cref="IGovernanceProvider"/>` |
| Handler -> Service | `<seealso cref="GovernanceService"/>` |
| Provider -> Factory | `<seealso cref="IGovernanceProviderFactory"/>` |
| Test -> Subject | `<seealso cref="AlationGovernanceProvider"/>` (in test class) |

---

## Files to Skip (Do Not Document)

| Category | Pattern | Reason |
|----------|---------|--------|
| Build artifacts | `obj/`, `bin/` | Auto-generated |
| Designer files | `*.Designer.cs` | Auto-generated |
| AutoRest output | `*REST.cs`, `*RESTExtensions.cs` | Auto-generated |
| AutoRest models | `PurviewApiClient/Models/*.cs` | Auto-generated |
| Assembly info | `AssemblyInfo.cs`, `GlobalUsings.g.cs` | Auto-generated |
| Files with attribute | `[GeneratedCode]` | Auto-generated |

---

## Example: Full "Orchestrator / Provider Selector" Class Header

```csharp
/// <summary>
/// Selects the appropriate metadata provider for a target system and orchestrates end-to-end sync execution.
/// </summary>
/// <remarks>
/// <para><b>Context</b>: Provides a single orchestration entry point over multiple provider implementations.</para>
/// <para><b>Responsibilities</b>:</para>
/// <list type="bullet">
///   <item><description>Resolve provider implementation from configuration and target metadata.</description></item>
///   <item><description>Execute sync phases in a stable order and emit consistent telemetry.</description></item>
/// </list>
/// <para><b>Non-goals</b>: Does not perform provider-specific API calls or data shaping (delegated).</para>
/// <para><b>Key invariants</b>: Provider resolution is deterministic; sync phases are ordered; operations are idempotent where possible.</para>
/// <para><b>Lifecycle &amp; concurrency</b>: Not thread-safe; one instance per request scope; no shared mutable state.</para>
/// <para><b>Error handling</b>: Provider exceptions are wrapped into domain errors; transient failures may be retried by caller policy.</para>
/// <para><b>Extensibility</b>: Add a provider by implementing IMetadataProvider and registering it in DI + configuration mapping.</para>
/// <para><b>Testing</b>: Unit-test selection and phase ordering; integration-test provider implementations against real endpoints.</para>
/// </remarks>
/// <seealso cref="IGovernanceProvider"/>
/// <seealso cref="PurviewGovernanceProvider"/>
/// <seealso cref="AlationGovernanceProvider"/>
public sealed class GovernanceProviderFactory : IGovernanceProviderFactory { }
```

---

## Reviewer Checklist

When reviewing class documentation, ensure it answers:

- [ ] What is the class boundary and responsibility?
- [ ] What does it explicitly not do (non-goals)?
- [ ] What invariants must remain true?
- [ ] How does it behave under failure (exceptions, retries, logging)?
- [ ] What are the key dependencies and assumptions?
- [ ] Is concurrency/lifecycle clear?
- [ ] Is extension guidance correct and safe?
- [ ] Does the testing guidance match the seams in the code?
- [ ] Are cross-references (`<seealso>`) included for related types?

---

## When to Update Documentation

Update the documentation when any of these change:

- Responsibilities/boundary
- Provider selection rules / orchestration order
- Error handling behavior or retry semantics
- Security or logging/redaction rules
- Thread-safety/lifecycle assumptions
- Extensibility mechanism (DI registration, config mapping)
- Dependencies on external systems
- Key invariants or assumptions

---

## Existing Documentation Policy

When documenting a class that already has partial documentation:

**Merge/Augment** - Do not replace existing documentation. Instead:

1. Keep existing accurate information
2. Add missing required sections
3. Restructure to match the standard format
4. Update outdated information
5. Add cross-references where appropriate

---

## Summary

| File Type | Documentation Level | Key Sections |
|-----------|---------------------|--------------|
| Interfaces | Full | Summary, Context, Implementations, Invariants |
| Abstract classes | Full | Summary, Context, For Implementers |
| Static helpers | Full | Summary, Context, Thread-safety |
| Concrete classes | Full | All standard sections |
| Message handlers | Full | Summary, Message, Trigger, Processing, Idempotency |
| Controllers | Full | Summary, Route, Auth, Endpoints |
| Test classes | Full | Summary, Coverage, Dependencies, Category |
| Partial files | Abbreviated | Summary referencing main file |
| Models/DTOs | Abbreviated | Summary, non-obvious properties |
| Enums | Abbreviated | Summary, value descriptions |
| Constants | Abbreviated | Summary, grouped logically |
| Auto-generated | Skip | Do not document |
