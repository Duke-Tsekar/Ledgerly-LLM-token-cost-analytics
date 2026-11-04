/*
===============================================================================
04 Validate Token Logic
===============================================================================
Purpose:
   - Validate cached tokens against prompt tokens
   - Check whether any row has negative uncached input tokens, which would distort cost.
===============================================================================
SQL dialect: DuckDB
===============================================================================
*/

-- Step: Run the validation or aggregation described in the purpose header and return the results.
SELECT
    COUNT(*) AS total_requests,
    COUNT(*) FILTER (
        WHERE cached_tokens > prompt_tokens
    ) AS cached_exceeds_prompt,
    COUNT(*) FILTER (
        WHERE cached_tokens < 0
    ) AS negative_cached_tokens,
    COUNT(*) FILTER (
        WHERE prompt_tokens < 0
    ) AS negative_prompt_tokens
FROM read_parquet('data/fact_llm_requests.parquet');