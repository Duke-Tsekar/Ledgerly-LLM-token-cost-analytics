/*
===============================================================================
03 Validate Pricing Table
===============================================================================
Purpose:
    - Inspect model pricing records for completeness and anomalies.
    - Check that each request matches exactly one effective-dated pricing record.
===============================================================================
SQL dialect: DuckDB
===============================================================================
*/
-- validate the pricing table for any inconsistencies or anomalies
SELECT *
FROM read_parquet('data/dim_price.parquet')
ORDER BY model, effective_from;



-- validate the effective-dated price join
WITH normalized_requests AS (
    SELECT
        request_id,
        ts_utc,
        CASE
            WHEN LOWER(TRIM(model)) = 'lg-1' THEN 'lg-1'
            WHEN LOWER(TRIM(model)) = 'md-1-latest' THEN 'md-1'
            WHEN LOWER(TRIM(model)) = 'md-1' THEN 'md-1'
            WHEN LOWER(TRIM(model)) = 'sm1' THEN 'sm-1'
            WHEN LOWER(TRIM(model)) = 'sm-1' THEN 'sm-1'
            WHEN LOWER(TRIM(model)) = 'md-2' THEN 'md-2'
            ELSE NULL
        END AS normalized_model
    FROM read_parquet('data/fact_llm_requests.parquet')
)
SELECT
    COUNT(*) AS total_requests,
    COUNT(p.model) AS matched_requests,
    COUNT(*) - COUNT(p.model) AS unmatched_requests
FROM normalized_requests r
LEFT JOIN read_parquet('data/dim_price.parquet') p
    ON r.normalized_model = p.model
   AND CAST(r.ts_utc AS DATE) >= CAST(p.effective_from AS DATE)
AND (
    p.effective_to IS NULL
    OR CAST(r.ts_utc AS DATE) <= CAST(p.effective_to AS DATE)
);


--- check for duplicate pricing matches
WITH normalized_requests AS (
    SELECT
        request_id,
        CAST(ts_utc AS DATE) AS request_date,
        CASE
            WHEN LOWER(TRIM(model)) = 'lg-1' THEN 'lg-1'
            WHEN LOWER(TRIM(model)) IN ('md-1', 'md-1-latest') THEN 'md-1'
            WHEN LOWER(TRIM(model)) IN ('sm-1', 'sm1') THEN 'sm-1'
            WHEN LOWER(TRIM(model)) = 'md-2' THEN 'md-2'
        END AS normalized_model
    FROM read_parquet('data/fact_llm_requests.parquet')
),
-- Step: Prepare the price matches intermediate result for the next analysis step.
price_matches AS (
    SELECT
        r.request_id,
        COUNT(p.model) AS price_match_count
    FROM normalized_requests r
    LEFT JOIN read_parquet('data/dim_price.parquet') p
        ON r.normalized_model = p.model
       AND r.request_date >= CAST(p.effective_from AS DATE)
       AND (
           p.effective_to IS NULL
           OR r.request_date <= CAST(p.effective_to AS DATE)
       )
    GROUP BY r.request_id
)
SELECT
    COUNT(*) AS total_requests,
    COUNT(*) FILTER (WHERE price_match_count = 0) AS no_price_match,
    COUNT(*) FILTER (WHERE price_match_count = 1) AS exactly_one_match,
    COUNT(*) FILTER (WHERE price_match_count > 1) AS multiple_price_matches
FROM price_matches;