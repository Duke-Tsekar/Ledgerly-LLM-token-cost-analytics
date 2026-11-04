/*
===============================================================================
05 Calculate Request Cost
===============================================================================
Purpose:
    - Normalize model identifiers and match requests to effective-dated prices.
    - Calculate request-level LLM API cost and write the result to data/fact_cost.parquet.
===============================================================================
SQL dialect: DuckDB
===============================================================================
*/

-- Output: data/fact_cost.parquet

COPY (
    WITH normalized_requests AS (
        SELECT
            *,
            CASE
                WHEN LOWER(TRIM(model)) = 'lg-1' THEN 'lg-1'
                WHEN LOWER(TRIM(model)) IN ('md-1', 'md-1-latest') THEN 'md-1'
                WHEN LOWER(TRIM(model)) IN ('sm-1', 'sm1') THEN 'sm-1'
                WHEN LOWER(TRIM(model)) = 'md-2' THEN 'md-2'
                ELSE NULL
            END AS normalized_model,
            CAST(ts_utc AS DATE) AS request_date
        FROM read_parquet('data/fact_llm_requests.parquet')
    ),

    -- Step: Match each request to the model price that was effective at the request timestamp.

    priced_requests AS (
        SELECT
            r.*,
            p.input_per_1m,
            p.cached_input_per_1m,
            p.output_per_1m
        FROM normalized_requests r
        LEFT JOIN read_parquet('data/dim_price.parquet') p
            ON r.normalized_model = p.model
           AND r.request_date >= CAST(p.effective_from AS DATE)
           AND (
               p.effective_to IS NULL
               OR r.request_date <= CAST(p.effective_to AS DATE)
           )
    )

    SELECT
        request_id,
        ts_utc,
        tenant_id,
        user_id,
        session_id,
        feature_id,
        model,
        normalized_model,
        status,
        retry_of,
        prompt_tokens,
        cached_tokens,
        completion_tokens,
        reasoning_tokens,

        CASE
            WHEN status = 'rate_limited' THEN 0.0
            ELSE (
                (prompt_tokens - cached_tokens) * input_per_1m
                + cached_tokens * cached_input_per_1m
                + (
                    COALESCE(completion_tokens, 0)
                    + COALESCE(reasoning_tokens, 0)
                ) * output_per_1m
            ) / 1000000.0
        END AS estimated_cost_usd

    FROM priced_requests
) TO 'data/fact_cost.parquet' (FORMAT PARQUET);
