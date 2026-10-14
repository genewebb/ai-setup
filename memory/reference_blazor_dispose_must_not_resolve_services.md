---
name: reference_blazor_dispose_must_not_resolve_services
description: A Blazor component that resolves optional services through IServiceProvider in a property getter crashes in Dispose (ObjectDisposedException) on every static render
metadata:
  type: reference
---
Speedy 9/23: StepsPage and ActiveRunIndicator used `Runs => Services.GetService(...)` getters and unsubscribed in Dispose via the getter. On a static SSR render the request scope's provider is already disposed when the component disposes, so every page request logged ObjectDisposedException ("Exceptions were encountered while disposing components"). bUnit never shows it; only a live host log did.

**How to apply:** resolve optional services ONCE in OnInitialized into a field; Dispose and timers use the field only. When checking a Speedy UI change, run a live host and grep its log for `fail:`, not just bUnit. Related [[reference_speedy_live_check_testbed_loopback]].
