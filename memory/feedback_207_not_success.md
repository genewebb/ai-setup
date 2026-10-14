---
name: Do not mask API errors as success
description: Never treat HTTP 207 MultiStatus or similar partial-success codes as success — that masks code errors
type: feedback
originSessionId: 6dd4a754-4cbb-467c-803e-cc19ab4738f2
---

Do not treat HTTP 207 MultiStatus as success in Profisee REST responses. A 207 means the code has an error (e.g., referencing attributes that don't exist on the entity). Masking it as success hides the bug.

**Why:** The user considers this a code error that should be surfaced and fixed, not worked around. The correct fix is to correct the attributes/payload, not to relax the success check.

**How to apply:** When encountering partial-success HTTP responses from Profisee, fix the root cause (wrong attributes, bad payload) rather than broadening the success criteria.
