/*
===============================================================================
31 Cache Savings By Model
===============================================================================
Purpose:
    - Estimate the maximum additional cache savings by model for eligible prompts.
    - Business use: Inform Finance's post-optimization spend forecast.
    - Estimate the maximum additional savings from caching.
===============================================================================
SQL dialect: DuckDB
===============================================================================
*/

-- Assumption: Prompts >= 1,024 tokens are cache-eligible.
-- This is an upper bound and not a forecast.

WITH eligible_requests AS (
    SELECT
        normalized_model,
        CAST(ts_utc AS TIMESTAMP) AS request_ts,
        prompt_tokens,
        cached_tokens
    FROM fact_cost
    WHERE prompt_tokens >= 1024
),
-- Prepare the priced intermediate result for the next analysis step.
priced AS (
    SELECT
        r.normalized_model,
        r.prompt_tokens,
        r.cached_tokens,
        p.input_per_1m,
        p.cached_input_per_1m
    FROM eligible_requests r
    JOIN read_parquet('data/dim_price.parquet') p
      ON r.normalized_model = p.model
     AND r.request_ts >= CAST(p.effective_from AS TIMESTAMP)
     AND (
         p.effective_to IS NULL
         OR r.request_ts < CAST(p.effective_to AS TIMESTAMP)
     )
)
SELECT
    normalized_model,
    COUNT(*) AS eligible_requests,
    SUM(prompt_tokens) AS eligible_prompt_tokens,
    SUM(cached_tokens) AS cached_tokens,
    ROUND(
        100.0 * SUM(cached_tokens)
        / NULLIF(SUM(prompt_tokens), 0),
        2
    ) AS observed_cache_token_pct,
    ROUND(
        SUM(
            GREATEST(prompt_tokens - cached_tokens, 0)
            * (input_per_1m - cached_input_per_1m)
            / 1000000.0
        ),
        2
    ) AS maximum_additional_savings_usd
FROM priced
GROUP BY normalized_model
ORDER BY maximum_additional_savings_usd DESC;
