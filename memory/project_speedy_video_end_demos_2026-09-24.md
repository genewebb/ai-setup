---
name: project-speedy-video-end-demos-2026-09-24
description: "Gene's 9/24 decisions for the two demos appended to speedy-complete.mp4 (dial up/down, codeless workflows) — built from mockups, 2-3 min each, NO \"not yet built\" disclosure"
metadata:
  node_type: memory
  type: project
  originSessionId: 87fb8af5-38c0-40da-8437-49fc39802b1c
  modified: 2026-09-25T00:35:46.001Z
---

Combined video = `walkthrough\speedy-complete.mp4` (intro + walkthrough, `video\build_combined.py`, PARTS list). Two demos go at the end:

- **Dial demo:** BOTH sources. `speedy\dial\02_DialBuilder_Capabilities.html` (v0.6 target design) for the why, then `speedy\ui\dial\dial-b.html` (Direction B, chosen at gate 66) as a recorded session plus an animated load chart for the how.
- **Codeless demo:** the shipped Steps view first, then the same flow in the Canvas mockups (`speedy\ui\crewchief\04-workloads\flow-canvas-*.html`).
- **Length:** 2-3 min each.
- **No disclosure** that it is not built yet. Gene: "it will be built, no need to disclose that it is not yet done". No badges, no "coming soon".

**Why:** the features aren't working yet, so the demos come from mockups plus animation. Gene treats them as committed product.

**How to apply:** every claim still traces to the mockup, the requirements or the code. Mockup data is fictional (`_assets/sample-data.js`); never present its numbers as measurements when reporting to Gene. Related: [[project_speedy_demo_diagrams]], [[feedback-call-it-speedy-with-speed-humor]], [[project_dial_builder_target_plan]], [[project-wvc-flow-canvas-decisions]].

**Built 2026-09-24:** `video\build_demos.py` + `diagrams\demos.json` -> dial 2:52, codeless 2:27, appended in `build_combined.py` PARTS -> `walkthrough\speedy-complete.mp4` 35:18, 18 chapters. Dial story follows dial-b's own numbers (Climb from 1, 6 rungs x 60 s, 1..32): break at 32, dial down to 16, up to 24. Monitor numbers are an illustrative model in `demos\site\live\dial-monitor.js`. Procedure: HowToUpdate.md 6.11.

**Shared package (9/24, later that evening):**
- Location: `C:\tmp\demo` (index.html home page, video\, diagrams\).
- Hosted at **http://smvmtr2/speedy/**: IIS default site, deployed by robocopy to `\\SMVMTR2\c$\inetpub\wwwroot\speedy`. HowToUpdate section 6.12.
- Gene's layout decisions:
  - One CTA at the top, "Take the narrated tour", which plays the full video.
  - Pit lane format first: the full tour, then Why Speedy / Architecture / Demos to rewatch.
  - A demos-only MP4 (`speedy-demos.mp4`).
- Why Speedy now has **9 laps**. The new lap 2, "Modern plumbing, all in containers", covers:
  - "the test harness itself is 100% container based" (Gene's framing; the Windows agent Setup package is out of scope);
  - no Hangfire, SQL does the work;
  - RabbitMQ's two real roles: the optional `--broker` mode, and the default self-test HTTP target.
