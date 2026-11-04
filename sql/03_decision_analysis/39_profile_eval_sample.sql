/*
===============================================================================
39 Profile Eval Sample
===============================================================================
Purpose:
    - Inspect the relationship between the model evaluated and the model that served each request.
    - Check whether the evaluation sample supports a like-for-like model-quality and cost comparison.
===============================================================================
SQL dialect: DuckDB
===============================================================================
*/

--  Run the validation or aggregation described in the purpose header and return the results.
SELECT
    e.model_tested,
    e.pass_fail,
    f.normalized_model AS served_model,
    COUNT(*) AS evaluation_count,
    ROUND(AVG(f.estimated_cost_usd), 6)
        AS avg_served_request_cost_usd,
    ROUND(SUM(f.estimated_cost_usd), 2)
        AS total_served_request_cost_usd
FROM read_parquet('data/eval_sample.parquet') AS e
JOIN fact_cost AS f
  ON e.request_id = f.request_id
GROUP BY
    e.model_tested,
    e.pass_fail,
    f.normalized_model
ORDER BY
    e.model_tested,
    f.normalized_model,
    e.pass_fail;
