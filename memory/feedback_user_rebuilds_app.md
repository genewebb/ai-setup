---
name: feedback-user-rebuilds-app
description: "User always stops and rebuilds/republishes the app themselves; don't do deployment mechanics"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 518d055b-d6ab-48e0-bb74-94b78489a323
---

The user always stops and rebuilds (and republishes) the TestAuto.Web app themselves after code changes. My responsibility ends at: correct source change + a clean build to verify it compiles.

**Why:** The app runs from `TestAuto.Web\bin\Release\publish\` and loads plugins from `bin\Release\publish\Plugins\`. `CopyToHosts` only refreshes `TestAuto.Web\Plugins\` (the dev/Debug location), not the publish folder — only `dotnet publish` refreshes what the running app uses. The user handles that cycle.

**How to apply:** Do NOT copy DLLs into publish folders, worry about file locks on the running instance, or walk through publish/restart steps. Just make the source fix, build (Debug or Release) to confirm 0 errors, and tell the user it's ready to pick up on their next rebuild. Plugin/host assemblies (TestAuto.Connect, TestAuto.Utilities, TestAuto.Web) all go live only on their rebuild/republish. Related: [[testauto-multistep-steps]] (plugin CopyToHosts note).

**Verifying a build while their instance is running (2026-08-25).** A plain `dotnet build` fails with MSB3027/MSB3021 "file is locked by" because the running host holds `bin\Debug\*.dll`. Do NOT kill their process. Redirect the output instead: `dotnet build <csproj> -c Debug --output <scratch-dir>`. The build (and any source generator, e.g. TDGAM's MD2Razor doc pipeline) runs in full, so it still proves the change compiles, and nothing in the repo bin folder is touched.
