---
name: feedback-tags-must-exist-in-testautotags
description: "Any tag put on a TestAuto workflow/scenario (including AUTO: automation IDs) must also be a record in the TestAutoTags entity"
metadata:
  node_type: memory
  type: feedback
  originSessionId: 8ecc9a58-e238-47c7-875f-417dfa1ed23f
  modified: 2026-11-05T23:44:57.724Z
---

Any tag I set on a TestAuto workflow, workflow detail or scenario must also exist as a record in the `TestAutoTags` entity on PROD. That includes the `AUTO:<machine>:<version>:<key>` automation IDs, size tags (1K, 10K...) and scenario tags.

**Why:** the Workflows page's tag filter only offers tags from TestAutoTags (`ReferenceCache.GetTags()`), so a tag that lives only in the workflow's Tags text can't be filtered on. Gene, 2026-11-05.
**How to apply:**
- After a pack generator upserts workflows, check for missing tags: STRING_SPLIT over `data.vTestAutoWorkflow.Tags`, NOT EXISTS in `data.vTestAutoTags`.
- Create any missing ones with IsActive Y and a description.
- TestAuto shows new tags only after its reference cache reloads.
- Tag Code = Name = the tag text.
- Related: [[project-matching-test-board-2026-11-05]], [[project-crewchief-packs-tags-2026-11-05]] (Connect pack status).
