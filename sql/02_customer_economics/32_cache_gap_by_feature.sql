/*
===============================================================================
32 Cache Gap By Feature
===============================================================================
Purpose:
    - Identify repeated prompt opportunities by tenant and feature within the defined cache window.
    - Rank features for further caching investigation; results are theoretical opportunities.
    - Business use: Prioritize caching improvements for Platform Engineering.
    - Savings are theoretical upper bounds, not forecast savings.
===============================================================================
SQL dialect: DuckDB
===============================================================================
*/
-- Assumptions: Eligible prompt >= 1,024 tokens; cache window = 5 minutes.

WITH request_gaps AS (
    SELECT
        request_id,
        tenant_id,
        feature_id,
        normalized_model,
        CAST(ts_utc AS TIMESTAMP) AS request_ts,
        prompt_tokens,
        cached_tokens,
        LAG(CAST(ts_utc AS TIMESTAMP)) OVER (
            PARTITION BY tenant_id, feature_id
            ORDER BY CAST(ts_utc AS TIMESTAMP), request_id
        ) AS previous_request_ts
    FROM fact_cost
    WHERE feature_id IS NOT NULL
),
-- Step: Prepare the eligible intermediate result for the next analysis step.
eligible AS (
    SELECT
        *,
        DATE_DIFF(
            'second',
            previous_request_ts,
            request_ts
        ) AS gap_seconds
    FROM request_gaps
    WHERE prompt_tokens >= 1024
),
-- Step: Prepare the priced intermediate result for the next analysis step.
priced AS (
    SELECT
        e.*,
        p.input_per_1m,
        p.cached_input_per_1m
    FROM eligible e
    JOIN read_parquet('data/dim_price.parquet') p
      ON e.normalized_model = p.model
     AND e.request_ts >= CAST(p.effective_from AS TIMESTAMP)
     AND (
         p.effective_to IS NULL
         OR e.request_ts < CAST(p.effective_to AS TIMESTAMP)
     )
)
SELECT
    feature_id AS feature,
    CASE
        WHEN previous_request_ts IS NULL THEN 'first_request'
        WHEN gap_seconds <= 60 THEN 'within_1_minute'
        WHEN gap_seconds <= 300 THEN '1_to_5_minutes'
        ELSE 'over_5_minutes'
    END AS gap_bucket,
    COUNT(*) AS eligible_requests,
    SUM(prompt_tokens) AS eligible_prompt_tokens,
    SUM(cached_tokens) AS cached_tokens,
    ROUND(
        100.0 * SUM(cached_tokens) / NULLIF(SUM(prompt_tokens), 0),
        2
    ) AS observed_cache_pct,
    ROUND(
        SUM(
            CASE
                WHEN gap_seconds BETWEEN 0 AND 300
                THEN GREATEST(prompt_tokens - cached_tokens, 0)
                     * (input_per_1m - cached_input_per_1m) / 1000000.0
                ELSE 0
            END
        ),
        2
    ) AS theoretical_savings_within_5m_usd
FROM priced
GROUP BY 1, 2
ORDER BY theoretical_savings_within_5m_usd DESC;
