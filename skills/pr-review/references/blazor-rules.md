# Blazor Rules Compliance Analysis

Verify adherence to Blazor and project rules defined in `.cursor/rules/`:

## Code-Behind Separation

- ✅ No direct `IRestClient` calls in `*.razor.cs` files
- ✅ Data access goes through dedicated services (e.g. `IWorkflowService`, `IScenarioService`)
- ✅ Services injected via `[Inject]`; no `RestClientFactory` in pages
- ❌ No `GetRecordsAsync`, `CreateRecordsAsync`, `UpdateRecordsAsync`, `DeleteRecordsAsync` in page code-behind
- ✅ Business logic in `TestAuto.Web/BusinessLogic/Services/`
- ✅ Result objects used (`IsSuccess`, `Data`, `ErrorMessage`) instead of exceptions for UI flow

## Constants for Entity and Field Names

- ✅ `EntityNames.*` and `FieldNames.*` used; no hard-coded entity/field strings
- ❌ No `"TestAutoWorkflow"`, `"Code"`, `[Workflow]` etc. as literals
- ✅ `FilterBuilder`, `QueryParameterBuilder` used for OData filters

## Approved Icons

- ✅ Icons from Material Symbols set (Radzen.Blazor); see `approved-icons.mdc`
- ❌ No Bootstrap icons (`diagram-3`, `pencil-square`, `box-arrow-up-right`)
- ✅ `edit` for edit actions, `account_tree` or `schema` for workflows, `open_in_new` for external links

## Component Structure

- ✅ `.razor` + `.razor.cs` for non-trivial components
- ✅ Logic in partial `.razor.cs`, not in `@code` blocks for complex pages
- ✅ `async` methods; avoid `async void` except event handlers
- ✅ DI for services; no service location

## Domain Values

- ❌ No hard-coded domain values (categories, statuses, etc.)
- ✅ Domain values from database or configuration via repository/lookup services

## String Constants

- ✅ Repeated string literals extracted to named constants (`LogConstants`, `EntityNames`, etc.)
- ❌ No inline log tag repetition; use `+` concatenation for Serilog (not `$"..."` for tags)
