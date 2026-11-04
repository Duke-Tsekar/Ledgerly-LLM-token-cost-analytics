/*
===============================================================================
18 Spend By Month
===============================================================================
Purpose:
    - Identify which normalized models drive monthly LLM spend.
    - Measure each model's contribution to monthly cost.
    - Business use: Explain spend growth and prioritize optimization.
===============================================================================
SQL dialect: DuckDB
===============================================================================
*/


-- Run the validation or aggregation described in the purpose header and return the results.
SELECT
    DATE_TRUNC('month', CAST(ts_utc AS TIMESTAMP)) AS spend_month,
    normalized_model,
    COUNT(*) AS request_attempts,
    ROUND(SUM(estimated_cost_usd), 2) AS total_cost_usd,
    ROUND(
        100.0 * SUM(estimated_cost_usd)
        / SUM(SUM(estimated_cost_usd)) OVER (
            PARTITION BY DATE_TRUNC('month', CAST(ts_utc AS TIMESTAMP))
        ),
        2
    ) AS monthly_cost_share_pct
FROM fact_cost
GROUP BY 1, 2
ORDER BY 1, 4 DESC;
