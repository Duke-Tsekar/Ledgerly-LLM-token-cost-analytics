/*
===============================================================================
07 Validate Cost By Status
===============================================================================
Purpose:
    - Summarize request counts and estimated cost by request status.
    - Check that billing treatment across successful and unsuccessful requests is consistent with the cost rules.
===============================================================================
SQL dialect: DuckDB
===============================================================================
*/

-- Step: Run the validation or aggregation described in the purpose header and return the results.
SELECT
    status,
    COUNT(*) AS request_count,
    SUM(estimated_cost_usd) AS total_cost_usd,
    AVG(estimated_cost_usd) AS average_cost_per_request_usd,
    COUNT(*) FILTER (
        WHERE estimated_cost_usd <> 0
    ) AS nonzero_cost_requests
FROM read_parquet('data/fact_cost.parquet')
GROUP BY status
ORDER BY status;


/*
our cost model currently assigns zero cost to rate_limited requests.
We need to verify that behavior and inspect the costs assigned to 
errors and timeouts before comparing our total against the synthetic invoice.
*/