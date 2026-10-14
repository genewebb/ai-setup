# Approved Icons Analysis (Blazor / Radzen)

Verify icon usage conforms to project rules in `.cursor/rules/blazor/ui/approved-icons.mdc`:

## Approved Icon Set

Icons must be from **Material Symbols** (Radzen.Blazor). Use only names from the approved list.

## Disallowed Icons

- ❌ Bootstrap icon names: `diagram-3`, `pencil-square`, `box-arrow-up-right`
- ❌ Font Awesome class names in Blazor components
- ❌ Custom or unapproved icon sets

## Semantic Replacements

| Disallowed | Use Instead |
|------------|-------------|
| `pencil-square` | `edit` |
| `box-arrow-up-right` | `open_in_new` |
| `diagram-3` | `account_tree` or `schema` |
| Generic Bootstrap | See approved-icons.mdc for full mapping |

## Detection

- Search for `BootstrapIcon`, `IconName="diagram-3"`, `IconName="pencil-square"`
- Search for Radzen `Icon` with non-approved names
- Check for Font Awesome `fa-` class usage in Blazor
- Flag any icon not in the approved Material Symbols list
