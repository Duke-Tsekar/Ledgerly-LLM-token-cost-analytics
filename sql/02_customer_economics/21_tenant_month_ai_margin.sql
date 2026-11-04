/*
===============================================================================
21 Tenant Month Ai Margin
===============================================================================
Purpose:
    - Calculate AI add-on revenue, customer-facing API cost, and margin by tenant and month.
    - Compare tenant economics across plans and identify where usage may not be covered
     by subscription revenue.
    - Business use: Target pricing changes at unprofitable segments.
===============================================================================
SQL dialect: DuckDB
===============================================================================
*/


/*
This directly supports Mariam’s decision about caps or tiered overage pricing
and helps Adaeze understand the customer-facing cost base.
*/


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
        t.ai_addon_mrr,
        c.customer_facing_cost_usd,
        t.ai_addon_mrr - c.customer_facing_cost_usd AS ai_margin_usd
    FROM tenant_month_cost AS c
    JOIN read_parquet('data/dim_tenant.parquet') AS t
        ON c.tenant_id = t.tenant_id
)
SELECT
    spend_month,
    plan_tier,
    COUNT(*) AS tenants_with_usage,
    COUNT(*) FILTER (WHERE ai_margin_usd < 0) AS underwater_tenants,
    ROUND(SUM(ai_margin_usd), 2) AS total_ai_margin_usd,
    ROUND(SUM(customer_facing_cost_usd), 2) AS customer_facing_cost_usd
FROM tenant_margins
GROUP BY 1, 2
ORDER BY 1, 2;
