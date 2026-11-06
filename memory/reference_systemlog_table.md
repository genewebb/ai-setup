---
name: reference-systemlog-table
description: Seq events are also stored in SQL - logging.tSystemLog in the Profisee DB and in PROD speedmerchants DB
metadata:
  type: reference
---

Everything in Seq is also in SQL, in the `logging.tSystemLog` table: in the Profisee DB, and in the PROD speedmerchants (ScenarioMgt) DB. Use it when Seq asks for a login or is unreachable. Gene, 2026-11-05.

Caveat seen the same day: the MCP `filter_table_names` tool did not list it (it only returned `__RefactorLog` for "Log"), so query the table directly. A search on PROD for the SourceSystemDistribution batch error returned 0 rows; it is unverified which events reach it.
