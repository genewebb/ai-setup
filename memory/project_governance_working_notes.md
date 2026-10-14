# Working Memory - Governance Project

## Governance Microservice Overview

**Location**: `c:\devops\repos\governance`

A .NET 8.0 governance microservice with data catalog integration (Purview, Alation). Multi-tier architecture with NServiceBus messaging and 2-tier caching (memory + distributed).

### Key Technologies

- **Framework**: ASP.NET Core 8.0
- **Messaging**: NServiceBus
- **Logging**: Serilog (structured logging)
- **Serialization**: Newtonsoft.Json ONLY (no System.Text.Json)
- **Caching**: Memory + Distributed (SQL Server)
- **Testing**: MSTest with 95+ test files
- **Authentication**: API Key handler

### Main Projects

1. `Governance` - Core DLL (netstandard2.0)
2. `Governance.Service.Api` - Main API service
3. `Governance.Testing` - Comprehensive test suite
4. `Governance.Alation` - Alation integration
5. `Governance.Common` - Shared utilities
6. `Governance.Cache` - Caching layer
7. `Utilities.Governance` - Public NuGet package

### Current State

- **Git Status**: 7 commits behind origin/main
- **Branch**: main
- **Uncommitted**: Modified .gitignore, untracked nul file
- **Recent Work**: Purview caching fixes, async/await refactoring

## Code Organization Pattern

- **Clean Architecture**: Controllers → Services → Providers
- **Provider Pattern**: GovernanceProviderFactory selects Purview or Alation
- **Large Partial Class**: GovernanceService split across 8 files (Upsert, Delete, Fetch, etc.)
- **Caching**: Two-tier with miss-storm prevention
- **Messaging**: NServiceBus for async state changes

## Critical Bug Areas

🔴 **High Priority**:

- **GovernanceService**: Large partial class with complex Upsert logic
- **Async/Await**: Recent refactoring from .Result (still may have issues)
- **Purview Integration**: Frequent API changes

🟡 **Medium Priority**:

- Cache invalidation timing
- Multi-instance isolation
- Provider-specific response parsing
- Relationship handling

## Code Quality Notes

✅ **Strengths**:

- Comprehensive test coverage (95+ tests)
- Interface-based design
- Dependency injection throughout
- Structured logging with correlation IDs
- Health check infrastructure

⚠️ **Areas for Bug Fixes**:

- Null checks in mapper helpers
- Error handling in async chains
- Cache key collision risks
- Instance isolation verification

## For Bug Fixing

1. **Before starting**: Pull latest (7 commits behind), run test suite baseline
2. **Investigation**: Use Serilog logs, check ExecutionId, review provider branching
3. **Focus areas**: Async patterns, null checks, cache keys, provider-specific logic
4. **Testing**: Run full test suite after changes

## Related Documentation

- Detailed review: `C:\devopslocal\Documentation\governance\Project_Review_Bug_Preparation.md`
- Testing framework: `C:\devopslocal\Documentation\governance\testing\Testing_Framework_Strategy.md`
- Copilot instructions: Require Serilog.ILogger (not Microsoft), Newtonsoft.Json only, MSTest only

## CRITICAL BUG FINDINGS (Mar 28, 2026)

**Alation Attributes Not Syncing - ROOT CAUSE IDENTIFIED**

**Root Cause**: Governance service NServiceBus message processing is completely stuck
- **407 total messages** stuck in main queue (not being processed)
- **159 MdmAttribute messages** pending (these are the missing attributes!)
- **28 MdmEntity messages** pending
- **72 messages** in error queue (possibly from earlier handler failures)

**Key Diagnostic Findings**:
1. ✅ **Entity cache working**: 179 entity cache entries confirmed (~31KB)
2. ✅ **Sync state correct**: EntityIdToName dictionary fully populated (position 7435 in JSON)
3. ❌ **Message handlers blocked**: No MdmAttribute/MdmEntity handler logs = messages never processed
4. ❌ **Health check failing**: TaskCanceledException (timeout on health check)
5. ❌ **Service degraded**: "Alation appears empty" warning (no tables found during resync)

**Queue Status**:
```
Governance Main Queue:    407 messages (including 159 attributes, 28 entities)
Governance Delayed Queue: 0 messages
Error Queue:              72 messages
```

**Message Types Stuck**:
- 159 × MdmAttribute messages (THESE DID NOT SYNC!)
- 28 × MdmEntity messages
- 214 × Unknown message types

**Impact**: The 159 attribute messages are physically in the queue but never processed because:
- GovernanceEndpoint configured for sequential processing (line 48 GovernanceEndpoint.cs)
- Handler appears to be blocked or crashed without logging
- Sequential mode = if first message fails, queue is deadlocked

**Investigation Status**: Need to check why handler is not processing queue

## User Preferences

- Always show full file paths when creating/referencing documents
