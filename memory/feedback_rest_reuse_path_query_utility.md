---
name: feedback-rest-reuse-path-query-utility
description: "REST calls must reuse the existing path/query builder for their client, never hand-roll URLs/query strings"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 518d055b-d6ab-48e0-bb74-94b78489a323
---

All REST calls must build their path and query string through the existing path/query utility for that client — never concatenate URLs or query strings ad hoc.

- Facades (`HttpClientFacade` subclasses): use `PathAndQueryBuilder` + `CallPostAsync`/`CallPatchAsync`/`CallDeleteAsync` (relative) or the `*FullPath` overloads (absolute).
- `ConnectRestClient` (non-facade): use its private `BuildPath(resource, extraSegments, queryParams)` helper (handles segment join, API-version prefix, and `HttpUtility.UrlEncode` of every key/value). All its methods go through it.
- Use existing constants for segments/attributes (`HttpRequestConstants.PathSegments`, `AttributeNames`, `ConnectConstants`) — not inline literals.

**Why:** one tested builder guarantees consistent encoding, segment joining, and gateway-version prefixing; hand-rolled URLs reintroduce encoding bugs (un-escaped filter values, double slashes) and drift from the gateway contract.

**How to apply:** when adding/reviewing any REST method, route it through the client's existing builder and mirror a sibling method (e.g. new `ConnectRestClient.FindLatestBatchByStrategyNameAsync` mirrors `GetBatchStatusAsync`). Codified in the [[testauto-http-facades]] skill ("Rule: reuse the path/query utility"). Related: [[testauto-connex-service]].
