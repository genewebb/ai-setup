---
name: reference-headless-edge-launcher-orphans
description: Killing a spawned headless msedge.exe PID (even /T tree) leaves the real browser running — close it via DevTools Browser.close (/json/version socket)
metadata:
  type: reference
---

A spawned `msedge.exe --headless` is only a launcher: it hands off to the real browser process and can exit first. `proc.kill()` and even `taskkill /PID <pid> /T /F` then miss the browser, which keeps running with its children. On 2026-09-24, 120 orphans had piled up, one burning over 1,000 s of CPU, and later recordings slowed down.

**Fix:** fetch `http://127.0.0.1:<port>/json/version`, open `webSocketDebuggerUrl`, send `{"method":"Browser.close"}`, then taskkill as a backstop. Helper: `speedmerchants\.vs\diagrams\video\edgeclose.mjs`.

**Clear old ones:** kill the roots, which are msedge.exe with `--headless` and no `--type=`, using `taskkill /T /F`. A normal Edge window never runs headless. Plain `Stop-Process` did nothing here.

Related: [[project_speedy_demo_diagrams]].
