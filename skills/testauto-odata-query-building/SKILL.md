---
name: testauto-odata-query-building
description: >
  OData filter and query construction helpers in TestAuto.Web. Use when building $filter
  expressions for Profisee REST record queries, combining AND/OR filters, filtering by date
  range, filtering by tag contains, constructing full query parameter dictionaries with
  Filter/PageSize/PageNumber/Select keys, or using QueryParameterBuilder to build paged
  requests.
---

Repo: speed-merchants (paths below are repo-relative)

# TestAuto OData Query Building

> **Scope**: speed-merchants (TestAuto.Web.BusinessLogic.Helpers)
> **Source**: `TestAuto.Web\BusinessLogic\Helpers\FilterBuilder.cs`

`FilterBuilder` is a static helper that constructs OData `$filter` strings for Profisee REST API record queries. Field names are wrapped in square brackets per Profisee OData conventions.

---

## FilterBuilder Methods

### `BuildEqualityFilter` — `[field] eq 'value'`

```csharp
var filter = FilterBuilder.BuildEqualityFilter("Status", "Active");
// → [Status] eq 'Active'
```

- Single quotes in the value are automatically escaped (`'` → `''`).
- Throws `ArgumentException` if `fieldName` is null/empty; `ArgumentNullException` if `value` is null.

---

### `BuildInFilter` — `[field] in ('v1', 'v2', ...)`

```csharp
var filter = FilterBuilder.BuildInFilter("Code", new[] { "A001", "A002", "A003" });
// → [Code] in ('A001', 'A002', 'A003')
```

- All values are quote-escaped.
- Throws `ArgumentException` if `values` is null or empty.

---

### `BuildDateRangeFilter` — `[field] ge 'start' and [field] le 'end'`

```csharp
var filter = FilterBuilder.BuildDateRangeFilter(
    "CreatedDate",
    startDate: DateTime.UtcNow.AddDays(-7),
    endDate: DateTime.UtcNow);
// → [CreatedDate] ge '2026-05-12T00:00:00.000Z' and [CreatedDate] le '2026-05-19T00:00:00.000Z'
```

- Either `startDate` or `endDate` may be null — only the provided bound is emitted.
- Both null → returns `string.Empty`.
- Dates are formatted as `yyyy-MM-ddTHH:mm:ss.fffZ`.

---

### `BuildTagContainsFilter` — `contains([field], 'value')`

```csharp
var filter = FilterBuilder.BuildTagContainsFilter("Tags", "high-priority");
// → contains([Tags], 'high-priority')
```

Used when tags are stored as comma-separated strings and you need a substring match.

---

### `CombineFilters` — AND composition

```csharp
var combined = FilterBuilder.CombineFilters(
    FilterBuilder.BuildEqualityFilter("Status", "Active"),
    FilterBuilder.BuildDateRangeFilter("CreatedDate", DateTime.UtcNow.AddDays(-30), null));
// → ([Status] eq 'Active' AND [CreatedDate] ge '...')
```

- Null/empty strings are silently ignored.
- Single valid filter returned as-is (no wrapping parentheses).
- Two or more valid filters wrapped: `(filter1 AND filter2 AND ...)`.

---

### `CombineFiltersWithOr` — OR composition

```csharp
var orFilter = FilterBuilder.CombineFiltersWithOr(
    FilterBuilder.BuildEqualityFilter("Type", "Customer"),
    FilterBuilder.BuildEqualityFilter("Type", "Prospect"));
// → ([Type] eq 'Customer' OR [Type] eq 'Prospect')
```

---

## Common Patterns

### Multiple conditions (AND)

```csharp
var filter = FilterBuilder.CombineFilters(
    FilterBuilder.BuildEqualityFilter("EntityName", "Customer"),
    FilterBuilder.BuildInFilter("Status", new[] { "Active", "Pending" }),
    FilterBuilder.BuildDateRangeFilter("ModifiedDate", cutoff, null));
```

### Tag filter combined with status

```csharp
var filter = FilterBuilder.CombineFilters(
    FilterBuilder.BuildEqualityFilter("Status", "Active"),
    FilterBuilder.BuildTagContainsFilter("Tags", "vip"));
```

### Passing the filter to a facade/query

```csharp
var filter = FilterBuilder.BuildEqualityFilter("Code", recordCode);
// Pass as $filter query parameter to the REST facade
var path = $"v1/Records/{entityName}?$filter={Uri.EscapeDataString(filter)}";
```

---

## Conventions

- Field names always go inside square brackets: `[FieldName]`. Do not add brackets yourself — `FilterBuilder` adds them.
- OData operators are lowercase: `eq`, `in`, `ge`, `le`. The `CombineFilters` methods use uppercase `AND`/`OR` in the wrapping expression — this matches Profisee's OData parser behavior.
- URL-encode the final filter string when passing as a query parameter: `Uri.EscapeDataString(filter)`.

---

## QueryParameterBuilder

`QueryParameterBuilder` builds the `Dictionary<string, string>` consumed by `PathAndQueryBuilder` (the facade's URL builder). Keys match the Profisee REST API query parameter names.

**Location**: `TestAuto.Web/BusinessLogic/Helpers/QueryParameterBuilder.cs`

### Methods

| Method | Keys emitted | Notes |
|---|---|---|
| `BuildFilterQuery(filter)` | `"Filter"` | Skips empty/null filter |
| `BuildPagingQuery(pageSize, pageNumber)` | `"PageSize"`, `"PageNumber"` | Skips if either is ≤ 0 |
| `BuildSelectQuery(fields)` | `"Select"` | Comma-joined field names |
| `Combine(params dicts)` | All keys merged | Later dicts override earlier on conflict |
| `BuildCompleteQuery(filter, pageSize, pageNumber, selectFields)` | All of the above | One-shot convenience method |

### Usage

```csharp
// Build paged, filtered query
var queryParams = QueryParameterBuilder.BuildCompleteQuery(
    filter:       FilterBuilder.BuildEqualityFilter("Status", "Active"),
    pageSize:     100,
    pageNumber:   1,
    selectFields: new[] { "Code", "Name", "Status" });
// → {"Filter": "[Status] eq 'Active'", "PageSize": "100", "PageNumber": "1", "Select": "Code,Name,Status"}

// Combine independently-built param sets
var queryParams = QueryParameterBuilder.Combine(
    QueryParameterBuilder.BuildFilterQuery(filter),
    QueryParameterBuilder.BuildPagingQuery(pageSize, pageNumber));
```

### When to use `QueryParameterBuilder` vs `FilterBuilder` directly

| Situation | Use |
|---|---|
| Building only the `$filter` expression | `FilterBuilder` |
| Building a full query dict (filter + paging + select) to pass to a facade | `QueryParameterBuilder` |
| Passing params to `PathAndQueryBuilder.WithQueryParameters(dict)` (or `AddQueryParameter(key, value)` for a single pair) | `QueryParameterBuilder` |

---

## Sources

- `TestAuto.Web\BusinessLogic\Helpers\FilterBuilder.cs` (`public static class FilterBuilder`, :9)
- `TestAuto.Web\BusinessLogic\Helpers\QueryParameterBuilder.cs` (`public static class QueryParameterBuilder`, :7) — **the one this skill documents**

> ⚠️ **Do not cite `TestAuto.Shared\Helpers\QueryExpressionBuilder.cs` as a source for this skill.**
> There is no type named `QueryExpressionBuilder` anywhere in the repo — a bare-name grep returns
> **zero** hits (checked 2026-07-27 @ 4c367fe6). The file exists, but it declares a *second,
> unrelated* `public static class QueryParameterBuilder` in namespace `TestAuto.Shared.Helpers`
> (`QueryExpressionBuilder.cs:3`) whose only member is
> `BuildQueryParameters(Dictionary<string,string> baseParameters, params (string key, string value)[] additionalParams)`
> — a plain dictionary merge with no OData, filter, or paging awareness. Grepping
> `BuildQueryParameters` finds the declaration and **no call sites**, so it is dead code and a
> name collision with the Web-side class. If you resolve `QueryParameterBuilder` and the methods
> in the table above are missing, you have picked up the `TestAuto.Shared.Helpers` one — check
> your `using`.
