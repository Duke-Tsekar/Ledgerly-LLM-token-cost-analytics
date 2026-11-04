/*
===============================================================================
20 Monthly Customer Facing Vs Internal
===============================================================================
Purpose:
    - Split monthly LLM spend into business usage categories: customer-facing,
      internal, and unattributed usage.
    -- Business use: Vendor commitment forecast and tenant pricing.
    - Show how business usage categories contribute to the vendor cost base.
===============================================================================
SQL dialect: DuckDB
===============================================================================
*/

-- Run the validation or aggregation described in the purpose header and return the results.
SELECT
    DATE_TRUNC('month', CAST(r.ts_utc AS TIMESTAMP)) AS spend_month,
    CASE
        WHEN r.feature_id IS NULL THEN 'unattributed'
        WHEN f.is_customer_facing THEN 'customer_facing'
        ELSE 'internal'
    END AS usage_category,
    COUNT(*) AS request_attempts,
    ROUND(SUM(r.estimated_cost_usd), 2) AS total_cost_usd
FROM fact_cost AS r
LEFT JOIN read_parquet('data/dim_feature.parquet') AS f
    ON r.feature_id = f.feature_id
GROUP BY 1, 2
ORDER BY 1, 2;
