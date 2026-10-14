---
name: reference-profisee-dba-is-entity-code
description: A Profisee DBA attribute stores the Code of another entity; Code default width is nvarchar(250)
metadata:
  type: reference
---

A **DBA attribute is a domain-based attribute — an entity reference.** Its stored value is literally the
**Code of the referenced entity**, not free text. The Profisee default width for `Code` is
**nvarchar(250)**, so a DBA column must be nvarchar(250) too.

**Why it matters:** a DBA column and the `Code` column of its lookup/reference table must be the SAME
width, because that pair is what a referential check joins on. Making the DBA column narrower than Code
means a full-length entity code cannot be stored; making it wider is merely wasteful but signals the
modeller misunderstood the relationship.

**How to apply:** treat DBA width as *derived from* Code width, never as an independent knob. In a
generator or schema tool, do not expose it as configurable — expose Code (or fix both) and let DBA follow.
Confirmed by the user 2026-08-18 while specifying TestData.Generation's column widths: Code 250, Name 250,
DBA 250 fixed by the system; only Text/Link/DateTime-scale/Number-precision remain adjustable.
Real `dbo.PDATA` predates this rule and uses nvarchar(50) DBAs, so exact schema parity with it is not
achievable — that difference is intended. See [[project_perftestdata_generator]].
