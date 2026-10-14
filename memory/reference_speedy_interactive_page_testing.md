---
name: reference_speedy_interactive_page_testing
description: "Speedy interactive (InteractiveServer) pages: prerender looks finished before clicks work, so the page exposes a data-*-interactive marker; browser/host harnesses must resolve the artifacts-path web build"
metadata: 
  node_type: memory
  type: reference
  originSessionId: e3dd5abf-c57e-4aff-8d75-e32e4cf90a27
  modified: 2026-09-21T21:07:46.252Z
---

Learned 2026-09-21 building `/steps` (the first InteractiveServer management screen after Monitor):

- **A prerendered interactive page looks finished before its buttons do anything.** Playwright can click the prerendered markup before the circuit connects, and those clicks do nothing. The Steps page sets `data-steps-interactive="true"` in `OnAfterRenderAsync(firstRender)`. Tests wait on `[data-speedy-steps][data-steps-interactive='true']` before interacting. Give every new interactive screen the same marker.
- **Kit components (`StepCard`, `FolderTree`, `ValueEditor`, `SegmentedToggle`) are EventCallback-based**, so they only work on interactive pages. The static-SSR screens (Reference data, Secrets) draw their own markup.
- **`StepCard` always draws Run and the Copy/Rename/Export/Delete menu.** A screen that doesn't honour those verbs must draw its own micro-card markup, or the kit needs `HasDelegate` gating first.
- **Builds use `--artifacts-path tests/bin/<name>-art`** because the developer's own speedy-web holds `src/Web/bin`. Both host harnesses resolve `<artifacts>/bin/Web/<config>/speedy-web.dll` first: `tests/Tests.Unit/ImportInputHostHarness.cs` and `tests/Tests.Browser/SpeedyWebHost.cs` (fixed 9/21). Without that, the browser suite silently ran the stale `src/Web/bin` build.
- **A review host for Gene on new code:** copy the web output to `C:\tmp\<name>-bin` (so the artifacts folder stays unlocked). Copy `C:\tmp\speedy-review` state (it holds his account and authenticator seed). Start it on a new port with the four required settings (Transport, Journal, Agent, WorkExecutor).

Related: [[reference_playwright_enhanced_nav_waitforloadstate]], [[feedback_speedy_workflow_layout_full_width]].
