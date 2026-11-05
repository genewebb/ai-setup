---
name: feedback-ca1416-expected-linux-transition
description: CA1416 platform-compatibility warnings (e.g. TestAuto.Web\Program.cs:140) are expected; do not report them as problems
metadata:
  node_type: memory
  type: feedback
  originSessionId: 8ecc9a58-e238-47c7-875f-417dfa1ed23f
  modified: 2026-11-05T14:14:41.289Z
---

CA1416 (Windows-only API) warnings in speed-merchants are desired and expected; do not list them as findings or try to fix them.

**Why:** Gene, 11/05/2026: "That is desired and expected as we transition to Linux." The warnings mark Windows-only code paths that the Linux move must deal with.

**How to apply:** When summarizing build warnings, skip CA1416. Don't suppress them either; they are the to-do list for the Linux transition.
