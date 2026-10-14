---
name: reference_radzen_datagrid_unsized_column_collapses
description: "Radzen DataGrid renders table-layout fixed, so a RadzenDataGridColumn with no Width collapses to zero once the sized columns outrun the container"
metadata: 
  node_type: memory
  type: reference
  originSessionId: ba5a3f2a-f1ed-4de8-8046-daf12e21eb54
  modified: 2026-09-08T14:57:27.413Z
---

Radzen.Blazor 7.1.7 renders every DataGrid table with `table-layout: fixed`
(`default-base.css:13894 / 14207 / 14911`). Declared widths are satisfied FIRST; a
`RadzenDataGridColumn` with no `Width` gets only the leftover — which is **zero** once the
sized columns' total exceeds the container. The column vanishes entirely, header included.

Bit CrewChief's Workloads list view (found 2026-09-08): `Name` was deliberately left unsized as
"the fill column"; adding the 160px `Folder` column pushed the sized total to 1104px and the
name disappeared. Fix = `Width="300px"` on Name.

Never leave a column unsized in a grid whose other columns are pixel-sized. Regression test must
assert every `th` carries a width in its `style` — asserting the header EXISTS passes either way,
because the markup is identical and the collapse only happens at CSS layout time, which bUnit
never runs.

Still latent: `Steps.razor`'s `Description` column is unsized (sized total 1244px) — collapses on
a narrow window.

Related: [[crewchief-web-ui]] card/list views.
