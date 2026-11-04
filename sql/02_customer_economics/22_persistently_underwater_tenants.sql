/*
===============================================================================
22 Persistently Underwater Tenants
===============================================================================
Purpose:
    - Identify tenants underwater (negative AI add-on margin)for two consecutive months.
    - Prioritize targeted pricing and product reviews instead of blanket usage caps.
===============================================================================
SQL dialect: DuckDB
===============================================================================
*/
-- This directly supports Mariam’s Q1 pricing decision and avoids reviewing thousands of rows.
WITH tenant_month_cost AS (
    SELECT
        DATE_TRUNC('month', CAST(r.ts_utc AS TIMESTAMP)) AS spend_month,
        r.tenant_id,
        SUM(r.estimated_cost_usd) AS customer_facing_cost_usd
    FROM fact_cost AS r
    JOIN read_parquet('data/dim_feature.parquet') AS f
        ON r.feature_id = f.feature_id
    WHERE f.is_customer_facing = TRUE
    GROUP BY 1, 2
),
-- Step: Prepare the tenant margins intermediate result for the next analysis step.
tenant_margins AS (
    SELECT
        c.spend_month,
        c.tenant_id,
        t.plan_tier,
        t.ai_addon_mrr - c.customer_facing_cost_usd AS ai_margin_usd
    FROM tenant_month_cost AS c
    JOIN read_parquet('data/dim_tenant.parquet') AS t
        ON c.tenant_id = t.tenant_id
),
-- Step: Prepare the with previous intermediate result for the next analysis step.
with_previous AS (
    SELECT
        *,
        LAG(spend_month) OVER (
            PARTITION BY tenant_id ORDER BY spend_month
        ) AS previous_month,
        LAG(ai_margin_usd) OVER (
            PARTITION BY tenant_id ORDER BY spend_month
        ) AS previous_margin
    FROM tenant_margins
)
SELECT
    plan_tier,
    COUNT(*) AS persistently_underwater_tenants
FROM with_previous
WHERE ai_margin_usd < 0
  AND previous_margin < 0
  AND spend_month = previous_month + INTERVAL '1 month'
GROUP BY plan_tier
ORDER BY plan_tier;