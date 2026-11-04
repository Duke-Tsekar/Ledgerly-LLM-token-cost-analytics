/*
===============================================================================
19 Monthly Volume And Token Intensity
===============================================================================
Purpose:
    - Separate request-volume growth from changes in average token intensity.
    - Provide context for the vendor commitment forecast.
    - Business use: Support the vendor commitment forecast.
===============================================================================
SQL dialect: DuckDB
===============================================================================
*/

-- Run the validation or aggregation described in the purpose header and return the results.
SELECT
    DATE_TRUNC('month', CAST(ts_utc AS TIMESTAMP)) AS spend_month,
    COUNT(*) AS total_attempts,
    ROUND(AVG(
        prompt_tokens + COALESCE(completion_tokens, 0)
        + COALESCE(reasoning_tokens, 0)
    ), 2) AS avg_tokens_per_attempt,
    ROUND(SUM(estimated_cost_usd), 2) AS total_cost_usd,
    ROUND(
        SUM(estimated_cost_usd) / COUNT(*),
        6
    ) AS cost_per_attempt_usd
FROM fact_cost
GROUP BY 1
ORDER BY 1;