/*
===============================================================================
30 Cache Savings Opportunity
===============================================================================
Purpose:
    - Estimate current prompt-cache usage and potential savings.
    - Business use: Inform post-optimization vendor spend forecast.
    - Establish the scale of potentially cacheable prompt volume.
===============================================================================
SQL dialect: DuckDB
===============================================================================
*/
-- Assumption: Prompts of at least 1,024 tokens are cache-eligible.

--  Run the validation or aggregation described in the purpose header and return the results.
SELECT
    normalized_model,
    COUNT(*) AS request_attempts,
    SUM(prompt_tokens) AS prompt_tokens,
    SUM(cached_tokens) AS cached_tokens,
    ROUND(
        100.0 * SUM(cached_tokens)
        / NULLIF(SUM(prompt_tokens), 0),
        2
    ) AS observed_cache_token_pct,
    ROUND(SUM(estimated_cost_usd), 2) AS total_cost_usd
FROM fact_cost
GROUP BY normalized_model
ORDER BY total_cost_usd DESC;