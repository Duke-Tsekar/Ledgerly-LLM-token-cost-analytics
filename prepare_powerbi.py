"""Export compact Power BI tables from the existing Ledgerly DuckDB project.

Run from any directory with:
  .venv\\Scripts\\python.exe prepare_powerbi.py

Expected layout:
  project root/ledgerly.duckdb
  project root/data/dim_feature.parquet
  project root/data/dim_tenant.parquet

The script does not regenerate data or modify analytical source tables.
"""
from pathlib import Path
import sys
import duckdb

ROOT = Path(__file__).resolve().parent
DB_PATH = ROOT / "ledgerly.duckdb"
DATA_DIR = ROOT / "data"
OUT_DIR = ROOT / "powerbi"

required = [DB_PATH, DATA_DIR / "dim_feature.parquet", DATA_DIR / "dim_tenant.parquet"]
missing = [str(p) for p in required if not p.exists()]
if missing:
    print("Missing required project files:", file=sys.stderr)
    print("\n".join(f"  - {p}" for p in missing), file=sys.stderr)
    print("\nPlace this script in your project root beside ledgerly.duckdb and data/.", file=sys.stderr)
    sys.exit(1)

OUT_DIR.mkdir(exist_ok=True)
con = duckdb.connect(str(DB_PATH), read_only=True)

# Check the existing view before exporting anything.
try:
    con.execute("SELECT request_id, ts_utc, tenant_id, feature_id, normalized_model, status, estimated_cost_usd FROM fact_cost LIMIT 1")
except Exception as exc:
    raise SystemExit(
        "The DuckDB database does not expose the expected fact_cost view. "
        "Open the project database and run sql/10_create_fact_cost_view.sql first.\n"
        f"DuckDB said: {exc}"
    )

exports = {
    "monthly_spend.csv": r"""
        WITH monthly AS (
            SELECT date_trunc('month', ts_utc)::DATE AS month,
                   COUNT(*) AS total_attempts,
                   COUNT(*) FILTER (WHERE status = 'ok') AS successful_attempts,
                   COUNT(*) FILTER (WHERE status <> 'ok') AS unsuccessful_attempts,
                   SUM(estimated_cost_usd) AS total_cost_usd,
                   SUM(estimated_cost_usd) FILTER (WHERE status = 'ok') AS successful_cost_usd,
                   SUM(estimated_cost_usd) FILTER (WHERE status <> 'ok') AS unsuccessful_cost_usd,
                   SUM(prompt_tokens + cached_tokens + completion_tokens + reasoning_tokens) AS total_tokens
            FROM fact_cost
            GROUP BY 1
        )
        SELECT *, total_cost_usd / NULLIF(total_attempts, 0) AS cost_per_attempt_usd
        FROM monthly ORDER BY month
    """,
    "monthly_model_spend.csv": r"""
        SELECT date_trunc('month', ts_utc)::DATE AS month,
               normalized_model AS model,
               COUNT(*) AS attempts,
               SUM(estimated_cost_usd) AS cost_usd,
               SUM(estimated_cost_usd) / NULLIF(SUM(SUM(estimated_cost_usd)) OVER (PARTITION BY date_trunc('month', ts_utc)::DATE), 0) AS monthly_cost_share
        FROM fact_cost
        GROUP BY 1, 2
        ORDER BY 1, 4 DESC
    """,
    "monthly_audience_spend.csv": r"""
        WITH tagged AS (
            SELECT date_trunc('month', f.ts_utc)::DATE AS month,
                   CASE WHEN d.is_customer_facing THEN 'Customer-facing'
                        WHEN d.feature_id IS NULL OR f.feature_id IS NULL THEN 'Unattributed'
                        ELSE 'Internal' END AS audience,
                   f.request_id, f.estimated_cost_usd
            FROM fact_cost f
            LEFT JOIN read_parquet('data/dim_feature.parquet') d
              ON f.feature_id = d.feature_id
        )
        SELECT month, audience, COUNT(*) AS attempts,
               SUM(estimated_cost_usd) AS cost_usd
        FROM tagged GROUP BY 1, 2 ORDER BY 1, 2
    """,
    "tenant_month_margin.csv": r"""
        WITH customer_cost AS (
            SELECT date_trunc('month', f.ts_utc)::DATE AS month,
                   f.tenant_id,
                   SUM(f.estimated_cost_usd) AS customer_facing_cost_usd,
                   COUNT(*) AS customer_facing_attempts
            FROM fact_cost f
            JOIN read_parquet('data/dim_feature.parquet') d
              ON f.feature_id = d.feature_id AND d.is_customer_facing = TRUE
            GROUP BY 1, 2
        ),
        tenant_month AS (
            SELECT c.month, c.tenant_id, t.plan_tier, t.seats, t.ai_addon_mrr,
                   c.customer_facing_cost_usd, c.customer_facing_attempts,
                   t.ai_addon_mrr - c.customer_facing_cost_usd AS ai_margin_usd
            FROM customer_cost c
            JOIN read_parquet('data/dim_tenant.parquet') t USING (tenant_id)
        ),
        sequenced AS (
            SELECT *,
                   LAG(month) OVER (PARTITION BY tenant_id ORDER BY month) AS previous_observed_month,
                   LAG(ai_margin_usd) OVER (PARTITION BY tenant_id ORDER BY month) AS previous_ai_margin_usd,
                   ROW_NUMBER() OVER (PARTITION BY tenant_id ORDER BY month) AS observed_month_number
            FROM tenant_month
        )
        SELECT *,
               (ai_margin_usd < 0 AND previous_ai_margin_usd < 0
                AND previous_observed_month = (month - INTERVAL '1 month')::DATE
                AND observed_month_number > 2) AS underwater_two_consecutive_months
        FROM sequenced ORDER BY tenant_id, month
    """,
    "cap_rollout_cohorts.csv": r"""
        SELECT tenant_id, wave, cap_start_date, cap_level
        FROM read_parquet('data/cap_rollout.parquet')
        ORDER BY cap_start_date, tenant_id
    """,
    "commitment_scenarios.csv": r"""
        WITH assumptions AS (
            SELECT * FROM (VALUES
                ('Flat', 0.00),
                ('2% monthly growth', 0.02),
                ('4% monthly growth', 0.04),
                ('6% monthly growth', 0.06)
            ) AS g(growth_scenario, monthly_growth_rate)
        ),
        optimizations AS (
            SELECT * FROM (VALUES
                ('No optimization', 0.00),
                ('10% usage reduction', 0.10),
                ('30% usage reduction', 0.30)
            ) AS o(optimization_scenario, usage_reduction_rate)
        ),
        september_baseline AS (
            SELECT SUM(estimated_cost_usd) AS september_list_spend_usd
            FROM fact_cost
            WHERE ts_utc >= TIMESTAMP '2026-09-01 00:00:00'
              AND ts_utc <  TIMESTAMP '2026-10-01 00:00:00'
        ),
        monthly_projection AS (
            SELECT
                a.growth_scenario,
                a.monthly_growth_rate,
                o.optimization_scenario,
                o.usage_reduction_rate,
                gs.month_number,
                b.september_list_spend_usd
                  * POWER(1 + a.monthly_growth_rate, gs.month_number)
                  * (1 - o.usage_reduction_rate) AS projected_list_usage_usd
            FROM assumptions a
            CROSS JOIN optimizations o
            CROSS JOIN generate_series(1, 12) AS gs(month_number)
            CROSS JOIN september_baseline b
        ),
        annual_scenarios AS (
            SELECT
                growth_scenario,
                monthly_growth_rate,
                optimization_scenario,
                usage_reduction_rate,
                SUM(projected_list_usage_usd) AS annual_list_usage_usd
            FROM monthly_projection
            GROUP BY 1, 2, 3, 4
        )
        SELECT
            growth_scenario,
            monthly_growth_rate,
            optimization_scenario,
            usage_reduction_rate,
            ROUND(annual_list_usage_usd, 2) AS annual_list_usage_usd,
            ROUND(annual_list_usage_usd, 2) AS payg_cost_usd,
            ROUND(GREATEST(360000.00, 0.85 * annual_list_usage_usd), 2) AS contract_cost_usd,
            ROUND(annual_list_usage_usd - GREATEST(360000.00, 0.85 * annual_list_usage_usd), 2) AS estimated_savings_usd
        FROM annual_scenarios
        ORDER BY monthly_growth_rate, usage_reduction_rate
    """,
}

for filename, query in exports.items():
    output = OUT_DIR / filename
    # Resolve parquet paths from the project root, regardless of where the script was launched.
    query = query.replace("'data/", f"'{DATA_DIR.as_posix()}/")
    result = con.execute(query).fetchdf()
    result.to_csv(output, index=False)
    print(f"Wrote {output.relative_to(ROOT)} — {len(result):,} rows, {len(result.columns)} columns")

con.close()
print(f"\nFinished. Import the CSV files from: {OUT_DIR}")
