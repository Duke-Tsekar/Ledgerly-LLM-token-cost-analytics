/*
===============================================================================
17 Monthly Spend Baseline
===============================================================================
Purpose:
    - Establish the monthly LLM spend baseline for Finance.
    - Compare total, successful, and unsuccessful request cost over time.
    - Business use: Vendor commitment and pricing decisions.
===============================================================================
SQL dialect: DuckDB
===============================================================================
*/

--  Run the validation or aggregation described in the purpose header and return the results.
SELECT
    DATE_TRUNC('month', CAST(ts_utc AS TIMESTAMP)) AS spend_month,
    COUNT(*) AS total_attempts,
    COUNT(*) FILTER (WHERE status = 'ok') AS successful_attempts,
    COUNT(*) FILTER (WHERE status <> 'ok') AS unsuccessful_attempts,
    ROUND(SUM(estimated_cost_usd), 2) AS total_cost_usd,
    ROUND(SUM(estimated_cost_usd) FILTER (
        WHERE status = 'ok'
    ), 2) AS successful_attempt_cost_usd,
    ROUND(SUM(estimated_cost_usd) FILTER (
        WHERE status <> 'ok'
    ), 2) AS unsuccessful_attempt_cost_usd
FROM fact_cost
GROUP BY 1
ORDER BY 1;
