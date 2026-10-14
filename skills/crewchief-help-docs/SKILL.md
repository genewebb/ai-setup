---
name: crewchief-help-docs
description: >
  CrewChief's in-app help system — the Documentation/ embedded markdown corpus, its required YAML
  front-matter contract, DocsCatalog indexing/nav/search, and MarkdownDocBase/HelpLayout rendering. Use when
  adding or editing a CrewChief in-app help doc, when a doc does not appear in the nav, when ordering or
  categorising help pages, when wiring the EmbeddedResource glob, or when linking a step guide from
  UtilityStepTypeInfo.GetHelpSlug.
---

Repo: speed-merchants (paths below are repo-relative)

# CrewChief Help Docs

CrewChief ships its operator documentation **inside the app**: markdown files under
`CrewChief.Web/Documentation/`, embedded at build time and rendered at `/help/...`. This is the CrewChief
sibling of [[testauto-help-docs]] — same idea, separate implementation.

## When to Use

- Adding a new in-app help doc or step guide.
- "I added a doc and it does not show up in the nav."
- Changing a doc's category, ordering, or URL.
- Wiring `UtilityStepTypeInfo.GetHelpSlug` for a new step type.
- Touching the `Documentation/**/*.md` `EmbeddedResource` glob.

## The front-matter contract

Every doc needs YAML front matter. `DocsCatalog` (`CrewChief.Web/Services/Docs/DocsCatalog.cs`) parses it
after normalising CRLF (`:82`), so line endings never matter.

| Key | Required? | Behaviour if absent |
|---|---|---|
| `url` | **YES** | **The doc is silently dropped from the catalog** (`:86`) |
| `title` | No | Falls back to `url` (`:89`) |
| `category` | No | Defaults to `"Other"` (`:91`) |
| `order` | No | Sorts as its default; ties break on `Title` (`:100`) |
| `summary` | No | Empty string |
| `tags` | No | Empty list |
| `$layout` | Yes, by convention | `CrewChief.Web.Components.Help.HelpLayout` |

> [!warning] A missing `url` fails silently
> `if (fm is null || string.IsNullOrWhiteSpace(fm.Url)) continue;` — no error, no log, no page. If a doc
> you just added is not in the nav, check `url` **first**. A malformed YAML block behaves the same way: the
> `catch { continue; }` at `:85` swallows the parse failure.

## The `NN_` filename prefix is cosmetic

Ordering comes **only** from the `order` front-matter value: `.OrderBy(d => d.Order).ThenBy(d => d.Title)`,
then grouped by category (`:99-103`). The numeric filename prefix is a human convenience for browsing the
folder and nothing more.

Do not infer sequence from filenames. In the live corpus `46_` is order 105, `48_` is order 121, `47_` is
order 295, `raw-json-panes.md` carries no prefix at all, and both `21_` and `30_` prefixes are **duplicated**
across different files. All of that is fine, because the prefix is not the contract.

## Embedding

Docs are embedded via the `Documentation/**/*.md` `EmbeddedResource` glob in `CrewChief.Web.csproj` with a
**bare-filename `LogicalName`**. Two consequences:

1. Adding a doc needs **no** per-file csproj entry — drop the `.md` in and rebuild.
2. Because the logical name is the bare filename, **two docs may never share a filename across subfolders**;
   a collision is a hard build error. (The same rule governs shipped sample content — see
   [[crewchief-default-templates]].)

Rendering goes through `MarkdownDocBase` (`Components/Help/MarkdownDocBase.cs`) with `HelpLayout` as the
`$layout`, built by the `MD2RazorGenerator` package listed in [[crewchief-architecture]]'s tech-stack table.

## Step guides

`UtilityStepTypeInfo.GetHelpSlug(type)` maps a step type to `/help/step-guides/<slug>`, so a new step type
should ship a matching step-guide doc as part of its indivisible set — see
[[crewchief-adding-a-step-type]].

## Sources

- `CrewChief\CrewChief.Web\Services\Docs\DocsCatalog.cs`
- `CrewChief\CrewChief.Web\Components\Help\MarkdownDocBase.cs`
- `CrewChief\CrewChief.Web\CrewChief.Web.csproj` (Documentation EmbeddedResource glob)
- `CrewChief\CrewChief.Web\Documentation\` (the corpus)

## Related

[[testauto-help-docs]] · [[crewchief-architecture]] · [[crewchief-web-ui]] · [[crewchief-adding-a-step-type]] · [[markdown-code-blocks]]
