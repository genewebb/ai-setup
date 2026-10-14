#!/usr/bin/env python3
"""
build_comparison_sql.py — emit tidy (long-format) CRUD comparison SQL for N Profisee versions.

Why this exists
---------------
Comparing 1..N versions requires (a) an apples-to-apples "common runs" filter so a
Scenario/Operation/Rules row only counts fine-grained (AttributeCount x UserLoad) combos
that EVERY selected version actually ran, and (b) a consistent aggregation up to one row
per (Scenario, Operation, Rules, Version). That filter is easy to get subtly wrong by hand,
so it lives here as deterministic code. The query returns LONG format (one row per version);
the agent pivots it into the wide markdown table, which keeps the SQL stable for any N.

Usage
-----
    python build_comparison_sql.py --versions 26R1 26R2P
    python build_comparison_sql.py --versions 25R4 26R1 26R2P --metric batch
    python build_comparison_sql.py --versions 25R3 25R4 --metric user

--metric: batch | user | both   (default: both)

Output: SQL text on stdout. Run each statement via the speedmerchants-prod-mssql MCP
execute_query tool. The baseline for deltas is the FIRST version listed.
"""
import argparse
import re
import sys

# Profisee release tags look like 25R1, 25R2, 26R1, 26R2P (optional trailing letter),
# and patched-build variants like 26R2PV2 (optional trailing V<digits>).
VERSION_RE = re.compile(r"^[0-9]{2}R[0-9][A-Z]?(?:V[0-9]+)?$")

VIEWS = {
    "batch": "perfDashboard.vBatchCrudSummary",
    "user": "perfDashboard.vUserCrudSummary",
}


def validate(versions):
    if not versions:
        sys.exit("ERROR: at least one --versions value is required.")
    seen = set()
    for v in versions:
        if not VERSION_RE.match(v):
            sys.exit(f"ERROR: '{v}' is not a valid version tag (expected like 26R1, 26R2P).")
        if v in seen:
            sys.exit(f"ERROR: duplicate version '{v}'.")
        seen.add(v)


def build_sql(view, versions):
    n = len(versions)
    in_list = ", ".join(f"'{v}'" for v in versions)
    # Fine-grained combo key = Scenario, Operation, RuleCount, AttributeCount, [User Load].
    # common CTE keeps only combos that exist for ALL N versions (= apples-to-apples).
    return f"""\
WITH base AS (
    SELECT Scenario, Operation, RuleCount, AttributeCount, [User Load] AS UserLoad, PlatformVersion,
           WinsorizedAvgResponseTimeMs, P50ResponseTimeMs, P95ResponseTimeMs, Throughput, RuleCountSort
    FROM {view}
    WHERE PlatformVersion IN ({in_list})
),
combo AS (
    SELECT Scenario, Operation, RuleCount, AttributeCount, UserLoad, PlatformVersion,
           AVG(WinsorizedAvgResponseTimeMs) AS WinAvg,
           AVG(P50ResponseTimeMs)           AS P50,
           AVG(P95ResponseTimeMs)           AS P95,
           AVG(Throughput)                  AS Throughput,
           MAX(RuleCountSort)               AS RuleCountSort
    FROM base
    GROUP BY Scenario, Operation, RuleCount, AttributeCount, UserLoad, PlatformVersion
),
common AS (
    SELECT Scenario, Operation, RuleCount, AttributeCount, UserLoad
    FROM combo
    GROUP BY Scenario, Operation, RuleCount, AttributeCount, UserLoad
    HAVING COUNT(DISTINCT PlatformVersion) = {n}
)
SELECT c.Scenario, c.Operation, c.RuleCount, c.PlatformVersion,
       COUNT(*)                                   AS ComboCount,
       CAST(AVG(c.WinAvg)     AS DECIMAL(18,2))    AS WinsorizedAvgMs,
       CAST(AVG(c.P50)        AS DECIMAL(18,2))    AS P50Ms,
       CAST(AVG(c.P95)        AS DECIMAL(18,2))    AS P95Ms,
       CAST(AVG(c.Throughput) AS DECIMAL(18,2))    AS ThroughputRecPerSec,
       MAX(c.RuleCountSort)                        AS RuleCountSort
FROM combo c
INNER JOIN common m
    ON  m.Scenario       = c.Scenario
    AND m.Operation      = c.Operation
    AND m.RuleCount      = c.RuleCount
    AND m.AttributeCount = c.AttributeCount
    AND m.UserLoad       = c.UserLoad
GROUP BY c.Scenario, c.Operation, c.RuleCount, c.PlatformVersion
ORDER BY c.Scenario, MAX(c.RuleCountSort) DESC, c.Operation, c.PlatformVersion;"""


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--versions", nargs="+", required=True,
                    help="Versions oldest->newest; first is the delta baseline (e.g. 26R1 26R2P)")
    ap.add_argument("--metric", choices=["batch", "user", "both"], default="both")
    args = ap.parse_args()

    validate(args.versions)
    metrics = ["batch", "user"] if args.metric == "both" else [args.metric]

    print(f"-- Versions: {', '.join(args.versions)}  |  Baseline (delta reference): {args.versions[0]}")
    for m in metrics:
        print(f"\n-- ===== {m.upper()} CRUD =====")
        print(build_sql(VIEWS[m], args.versions))


if __name__ == "__main__":
    main()
