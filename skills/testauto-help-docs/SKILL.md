---
name: testauto-help-docs
description: >
  In-app MD2Razor help/documentation system, used by FOUR hosts (TestAuto.Web, CrewChief.Web,
  TestData.Mutation.Web, TestData.Generation.Web - each needs its OWN layout class, base class and JS
  namespace). Use when adding or
  editing in-app help docs, defining front-matter, debugging doc routing/search/links/mermaid,
  wiring the MD2Razor build pipeline, configuring EmbeddedResource/LogicalName for doc shipping,
  or understanding DocsCatalog nav/search behaviour.
---

# testauto-help-docs

## When to Use

- Adding a new `Documentation/*.md` page to the in-app help system
- Editing front-matter fields (title, url, category, order, summary, tags, $layout)
- Debugging why a doc does not appear in the nav or search index
- Debugging doc-to-doc or source-code link rewriting in rendered help pages
- Debugging mermaid diagrams not rendering inside the help viewer
- Adding the `.csproj` wiring for a new doc (EmbeddedResource, LogicalName)
- Understanding how `DocsCatalog` reads, groups, and searches docs at runtime
- Tracing the `help-docs.js` link-rewrite or anchor-intercept logic

For Mermaid-vs-ASCII diagram choice see [[markdown-code-blocks]] (Rule 11). The front-matter system and runtime pipeline are covered here.

---

## 1. Overview — Build-Time Pipeline

Each `.md` file under `TestAuto.Web/Documentation/` goes through two independent build-time steps:

| Step | Tool | What it produces |
|------|------|-----------------|
| Razor generator | `MD2RazorGenerator` NuGet | A routable `.razor` page inheriting `MarkdownDocBase` (via `MD2RazorDefaultBaseClass`). The route is the `url` front-matter field. |
| Embedded resource | MSBuild `<EmbeddedResource>` | The raw `.md` file baked into the assembly DLL so `DocsCatalog` can read it at runtime for nav + search. |

At runtime `DocsCatalog` reads all embedded `.md` resources, parses their YAML front-matter, and builds:
- `Nav` — grouped, ordered navigation tree
- `FileMap` — `filename → route` dictionary passed to the JS link rewriter
- Full-text search index (markup-stripped body)

---

## 2. Front-Matter Schema

Every doc **must** start with a YAML front-matter block delimited by `---`:

```yaml
---
title: "Solution Inventory"
url: /help/architecture/solution-inventory
category: "Architecture & Internals"
order: 0
summary: "One-line description shown in search results and the /help landing tiles."
tags: [architecture, solution, inventory]
$layout: TestAuto.Web.Components.Help.HelpLayout
---
```

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `title` | string | yes | Nav link label and page title. Falls back to `url` if absent. |
| `url` | string | **yes** | Razor route for the generated page. Must be unique. Absence causes the doc to be silently skipped. |
| `category` | string | yes | Groups the doc in nav and on the `/help` landing grid. Defaults to `"Other"` if absent. |
| `order` | int | no | Primary sort key within a category. Ties are broken by `title` alphabetically. |
| `summary` | string | no | Shown in search result snippets and the `/help` landing card. |
| `tags` | string list | no | Matched during search alongside title, summary, and body. |
| `$layout` | string | yes | Must be `TestAuto.Web.Components.Help.HelpLayout`. The `$` prefix is MD2Razor's layout directive. |

**Parsing details (verified against `DocsCatalog.cs`):**
- Deserializer uses `CamelCaseNamingConvention` — field names must be camelCase in YAML.
- CRLF normalization: the YAML block has `\r` stripped before parsing so Windows-authored docs parse correctly.
- The regex that splits front-matter from body: `^\s*---\r?\n(.*?)\r?\n---\r?\n(.*)$` (Singleline).
- A doc with no matching front-matter block is silently ignored.

---

## 3. `.csproj` Wiring

Verified from `TestAuto.Web/TestAuto.Web.csproj` lines 100–121:

```xml
<!-- MD2RazorGenerator: packages and build wiring -->
<ItemGroup>
  <PackageReference Include="MD2RazorGenerator" />
  <PackageReference Include="YamlDotNet" />
</ItemGroup>

<PropertyGroup>
  <!-- Every generated doc page inherits this base class -->
  <MD2RazorDefaultBaseClass>TestAuto.Web.Components.Help.MarkdownDocBase</MD2RazorDefaultBaseClass>
  <!-- Restrict the generator to source docs only; prevents bin/obj copies
       from producing duplicate-route Razor classes -->
  <_MD2Razor_MarkdownFile_Pattern>Documentation\**\*.md</_MD2Razor_MarkdownFile_Pattern>
</PropertyGroup>

<ItemGroup>
  <!-- Remove from the SDK-default None glob first to avoid duplicate-item errors -->
  <None Remove="Documentation\**\*.md" />
  <!-- Embed the raw .md into the DLL so DocsCatalog can read front-matter + body at runtime -->
  <!-- LogicalName gives each resource a bare filename key so digit-leading names
       are not mangled by MSBuild -->
  <EmbeddedResource Include="Documentation\**\*.md">
    <LogicalName>%(Filename)%(Extension)</LogicalName>
  </EmbeddedResource>
</ItemGroup>
```

### Three Gotchas

**Gotcha A — EmbeddedResource, not Content.**
MD2RazorGenerator consumes the `.md` and emits a `.razor`; the original `.md` is stripped from `Content` items by the generator. To ship the raw source for runtime reading it must be separately listed as `<EmbeddedResource>`. Omitting this means `DocsCatalog` finds zero docs and the nav is empty.

**Gotcha B — `<LogicalName>` is required for digit-leading filenames.**
MSBuild mangles embedded resource names that start with a digit (e.g. `00_SolutionInventory.md` becomes something namespace-prefixed and dot-separated). Setting `<LogicalName>%(Filename)%(Extension)</LogicalName>` forces the resource key to the bare filename (`00_SolutionInventory.md`), which is what `DocsCatalog` uses as the `fileMap` key.

**Gotcha C — `_MD2Razor_MarkdownFile_Pattern` scope restriction.**
Without this property the generator would also pick up any `.md` copies in `bin/` or `obj/` directories and produce duplicate Razor classes with conflicting routes, causing a build error. Scoping to `Documentation\**\*.md` ensures only source files are processed.

---

## 4. DocsCatalog — Runtime Behaviour

**Source**: `TestAuto.Web/Services/Docs/DocsCatalog.cs`

### Startup (lazy, first access)

1. `ReadDocsFromEmbeddedResources` — iterates `Assembly.GetManifestResourceNames()`, keeps only names ending in `.md`, reads each to string.
2. `Build` — for each file:
   - Matches the front-matter regex; skips if no match.
   - Strips `\r` from the YAML block; deserializes with `FrontMatterDto` (camelCase).
   - Skips if `url` is null/empty.
   - Creates a `DocNode` record and adds `(node, strippedBody)` to the search index.
   - Adds `fileName → url` to `fileMap` (case-insensitive key).
3. Nav is built: `OrderBy(order).ThenBy(title).GroupBy(category).OrderBy(category)`.

### DocNode record

```csharp
record DocNode(string Title, string Url, string Category, int Order,
               string Summary, IReadOnlyList<string> Tags);
```

### Search

`IDocsCatalog.Search(string query)` — case-insensitive substring match against `Title`, `Summary`, `Tags`, and the markup-stripped body. Markup strip regex: `[#>*\`\[\]\(\)_-]` → space.

Snippet extraction: 160 characters centred on the first hit (60 chars before, remainder after), prefixed with `…` if truncated.

### Test seam

`DocsCatalog.BuildForTest(IReadOnlyDictionary<string, string> files)` bypasses the assembly resource read, accepting in-memory filename→content dictionaries. Use this in unit tests.

---

## 5. `help-docs.js` — Link Rewriting

**Source**: `TestAuto.Web/wwwroot/js/help-docs.js`  
**Entry point**: `window.testautoHelp.enhance(repoBaseUrl, branch, fileMap)`

Called from `MarkdownDocBase.OnAfterRenderAsync` (first render only) with:
- `repoBaseUrl` — from `Configuration["Documentation:RepoBrowserBaseUrl"]` (trimmed trailing `/`)
- `branch` — hardcoded `"main"`
- `fileMap` — `IDocsCatalog.FileMap` (filename → route dictionary)

The function is idempotent: already-processed anchors get `data-help-enhanced="1"` and are skipped on repeat calls.

### Link-rewrite rules (in order)

| Condition | Action |
|-----------|--------|
| `https?://` prefix | External — add `target="_blank" rel="noopener"` |
| `#...` (bare anchor) | In-page TOC — intercept click, `scrollIntoView`, update `history.replaceState`. Prevents `<base href="~/">` from sending navigation to the app root. |
| `*.md` basename in `fileMap` | Doc-to-doc — rewrite `href` to the registered route; `#anchor` appended if present |
| `*.md` NOT in `fileMap`, or `./` / `../` prefix | Source/cross-project link → Azure DevOps deep link |

### Azure DevOps deep-link construction

```
{repoBaseUrl}?path=/{repoPath}&version=GB{branch}
```

`repoPath` resolution rule:
- Strip leading `./` or `../` sequences.
- If the resulting path does NOT start with `TestAuto` or `Testing` (i.e. it is relative to `TestAuto.Web/`, not the repo root), prefix it with `TestAuto.Web/`.
- Examples:
  - `../TestAuto.Core/SomeFile.cs` → `TestAuto.Core/SomeFile.cs` (starts with `TestAuto`)
  - `./Services/Docs/DocsCatalog.cs` → `TestAuto.Web/Services/Docs/DocsCatalog.cs` (prefixed)

### Mermaid rendering

After link processing, if `window.mermaid` is available:

```js
window.mermaid.run({ querySelector: '.help-content pre.mermaid:not([data-processed="true"])' });
```

MD2Razor emits fenced code blocks tagged with `class="mermaid"` on the `<pre>` element. The `:not([data-processed="true"])` guard prevents re-rendering on subsequent enhancements.

---

## 6. MarkdownDocBase

**Source**: `TestAuto.Web/Components/Help/MarkdownDocBase.cs`

```csharp
public abstract class MarkdownDocBase : ComponentBase
{
    [Inject] public IJSRuntime JS { get; set; } = default!;
    [Inject] public IConfiguration Configuration { get; set; } = default!;
    [Inject] public IDocsCatalog Catalog { get; set; } = default!;

    private string RepoBaseUrl =>
        (Configuration["Documentation:RepoBrowserBaseUrl"] ?? string.Empty).TrimEnd('/');

    protected override async Task OnAfterRenderAsync(bool firstRender)
    {
        if (!firstRender) return;   // enhance once per page render
        await JS.InvokeVoidAsync("testautoHelp.enhance", RepoBaseUrl, "main", Catalog.FileMap);
    }
}
```

Key points:
- `firstRender` guard — safe for Blazor prerender; JS interop only runs after the DOM is live.
- Config key: `Documentation:RepoBrowserBaseUrl` — must be set in `appsettings.json` for source links to resolve.
- Every MD2Razor-generated page inherits this class automatically via the `MD2RazorDefaultBaseClass` MSBuild property.

---

## 7. HelpLayout and Navigation

**HelpLayout** (`TestAuto.Web/Components/Help/HelpLayout.razor`):
- Inherits `LayoutComponentBase`; nested inside `MainLayout` via `@layout TestAuto.Web.Components.Layout.MainLayout`.
- Renders a two-column shell: `<aside class="help-index-col">` (nav) + `<div class="help-main-col">` (content).
- Collapsible index: a toggle button switches `_indexCollapsed` bool → adds/removes CSS class `index-collapsed` on the shell wrapper. No JS needed — pure Blazor state.

**HelpNavigation** (`TestAuto.Web/Components/Help/HelpNavigation.razor`):
- Injects `IDocsCatalog`; renders `Catalog.Nav` (already grouped and ordered by `DocsCatalog.Build`).
- Uses `<NavLink Match="NavLinkMatch.All">` for active-link highlighting.
- Shows `"No documentation found."` if `Catalog.Nav` is empty (missing front-matter, EmbeddedResource not wired, etc.).

**HelpPage** (`/help` route):
- Landing page with full-text search box (live `oninput` binding → `Catalog.Search`).
- When no query: renders category tiles (up to 6 docs per category) from `Catalog.Nav`.
- When query is active: renders a flat `list-group` of `DocSearchResult` items with snippet.

---

## 8. Adding a New Help Doc — Checklist

0. **Content rule — no personal profile commands**: help docs must reference only the normal dev
   steps (shipped CLI verbs, standard `dotnet` commands, repo scripts) — NEVER the user's personal
   PowerShell profile wrappers (`dpTestAuto`, `dpcrewchief`, other `dp*` commands) or personal
   machine paths (the old `devopslocal` folders, or any drive-letter path). Other developers don't have them. Same rule for CrewChief's
   `Documentation/` help docs. See `ai-foundational-rules` Rule 5.

1. Create `TestAuto.Web/Documentation/MyDoc.md` with valid YAML front-matter (all required fields).
2. Verify the `.csproj` already has the `<EmbeddedResource Include="Documentation\**\*.md">` glob — it does; no per-file entry needed.
3. Set `$layout: TestAuto.Web.Components.Help.HelpLayout` in the front-matter.
4. Choose a unique `url` starting with `/help/`.
5. Pick a `category` matching an existing one (check `Catalog.Nav` group keys) for consistency, or introduce a new one.
6. Rebuild. The generator emits the routed Razor class; the EmbeddedResource includes the raw `.md`.
7. If doc is not in nav: check front-matter regex (must start file with `---\n`), check `url` is present, check the resource is embedded (use `asm.GetManifestResourceNames()` in a debug breakpoint).

---

## 9. Configuration

| Key | Location | Purpose |
|-----|----------|---------|
| `Documentation:RepoBrowserBaseUrl` | `appsettings.json` | Base URL for Azure DevOps repo browser (e.g. `https://dev.azure.com/org/project/_git/repo`). Without this, source links are stripped but the page still loads. |

---

## The pipeline now has FOUR hosts - scope the layout rule

The MD2Razor mechanics documented here are correct, but this skill was written TestAuto-first and the
layout directive is **host-specific**. Following it verbatim in another project produces a doc that
**will not render**.

| Host | Layout class | Base class | JS |
|---|---|---|---|
| TestAuto.Web | `TestAuto.Web.Components.Help.HelpLayout` | TestAuto's `MarkdownDocBase` | TestAuto's |
| CrewChief.Web | `CrewChief.Web.Components.Help.HelpLayout` | CrewChief's | `ccHelp` - see [[crewchief-help-docs]] |
| TestData.Mutation.Web | `TestData.Mutation.Web.Components.Help.HelpLayout` | its own | `tdm-help-docs.js` |
| TestData.Generation.Web | `TestData.Generation.Web.Components.Help.HelpLayout` | its own | `tdgHelp.enhance` |

TestData.Mutation.Web self-describes as "Ported from TestAuto.Web" and its csproj wiring is almost verbatim
the same - including the `None Remove` plus `EmbeddedResource`/`LogicalName` pair and the
digit-leading-filename gotcha. Only the three values above differ per host. See
[[testdata-generation-and-mutation-engine]] for those two products.

## Sources

- `TestAuto.Web/Components/Help/MarkdownDocBase.cs`
- `TestAuto.Web/Components/Help/HelpLayout.razor`
- `TestAuto.Web/Components/Help/HelpNavigation.razor`
- `TestAuto.Web/Components/Help/HelpPage.razor` + `HelpPage.razor.cs`
- `TestAuto.Web/Services/Docs/DocsCatalog.cs`
- `TestAuto.Web/Services/Docs/DocNode.cs`
- `TestAuto.Web/wwwroot/js/help-docs.js`
- `TestAuto.Web/TestAuto.Web.csproj` (lines 100–121)
- `TestAuto.Web/Documentation/00_SolutionInventory.md` (front-matter sample)
- `TestAuto.Web/Documentation/11_DeveloperGuide.md` (front-matter sample)
