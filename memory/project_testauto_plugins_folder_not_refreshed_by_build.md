---
name: project_testauto_plugins_folder_not_refreshed_by_build
description: "TestAuto.Web\\Plugins\\*.dll are hand-placed, git-untracked, and never refreshed by the build — TestAuto.Connect/Metadata/Records silently deploy stale while root DLLs look current"
metadata: 
  node_type: memory
  type: project
  originSessionId: f13c9ec0-3fe6-449d-9ed0-5d583a4a5bbb
  modified: 2026-08-06T13:12:24.419Z
---

`TestAuto.Web` loads scenario plugin assemblies from `Plugins\*.dll` via `Assembly.LoadFrom`
(`ScenarioManagementServiceExtensions.cs`, the `AppContext.BaseDirectory\Plugins` scan). **TestAuto.Connect,
TestAuto.Metadata and TestAuto.Records are NOT `ProjectReference`d by `TestAuto.Web.csproj`** — only
`TestAuto.Matching` and `TestAuto.Utilities` are.

Consequences:

1. `TestAuto.Web\Plugins\` is **not git-tracked**. The DLLs in it are hand-copied artifacts.
2. `TestAuto.Web.csproj` has `<Content Include="Plugins\**\*.dll">` with `CopyToPublishDirectory=Always`,
   so a publish **faithfully copies whatever stale binary sits there**.
3. A normal build/publish refreshes every root DLL and the project-referenced plugin copies, so
   `dir TestAuto.*` in the deploy root looks completely current while a plugin is hours or days behind.

Observed 2026-08-05 on the test box: deploy root all `21:12–21:13`, `Plugins\TestAuto.Matching.dll` and
`Plugins\TestAuto.Utilities.dll` `21:13`, but `Plugins\TestAuto.Connect.dll` `11:28` (a **Debug** build, 4h
before the PR 25042 merge at 15:31) and `Plugins\TestAuto.Metadata.dll` from **2026-07-27**.

**Verification recipe** — never trust the deploy root alone:

```
ls -l --time-style=full-iso <deploy>\Plugins\
git log -1 --date=iso-local --pretty='%h %ad %s'      # compare plugin mtime to the merge time
git diff --stat <commit-at-plugin-build-time> HEAD -- TestAuto.Connect TestAuto.Scenarios TestAuto.Shared
```

That last diff is the one that matters: it tells you the *functional* delta, which is usually far smaller
than the timestamp gap suggests. In the 2026-08-05 case the 4-hour-stale Connect plugin differed from HEAD by
exactly one line (`Workload = ScenarioName`), so it was **not** the cause of the step hang being investigated —
only a blank `Workload` Domain column. Removing a stale-binary confound is worth doing before deeper
debugging, but do not declare it the root cause without that diff.

**Cross-assembly hazard:** a plugin built at commit X is bound by `Assembly.LoadFrom` against host
`TestAuto.Shared`/`TestAuto.Scenarios` at HEAD. Any signature change in those between X and HEAD surfaces as
`MissingMethodException`/`TypeLoadException` at JIT time inside the scenario — which Hangfire then retries
silently, pinning the step in `Running`. See [[project_connect_postrun_cross_database_hang]] and
[[reference_hangfire_job_exception]].

**Durable fix (not yet done):** add a post-build/publish target that rebuilds the plugin projects and copies
their output into `Plugins\`, or `ProjectReference` them with `Private=false` plus an explicit copy. Until
then, plugin refresh is a manual step in every deploy.

Related: [[reference_bare_http_error_means_stale_build]], [[project_repos]],
[[feedback_user_rebuilds_app]]
