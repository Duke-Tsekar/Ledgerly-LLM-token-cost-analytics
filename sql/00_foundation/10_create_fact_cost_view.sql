/*
===============================================================================
10 Create Fact Cost View
===============================================================================
Purpose:
    - Create a reusable DuckDB view over the calculated request-level cost data.
===============================================================================
SQL dialect: DuckDB
===============================================================================
*/

CREATE OR REPLACE VIEW fact_cost AS
-- Step: Run the validation or aggregation described in the purpose header and return the results.
SELECT *
FROM read_parquet('data/fact_cost.parquet');
