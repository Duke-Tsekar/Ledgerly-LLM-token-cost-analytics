/*
===============================================================================
08 Profile Vendor Invoice
===============================================================================
Purpose:
    - Inspect the synthetic vendor invoice before reconciliation.
===============================================================================
SQL dialect: DuckDB
===============================================================================
*/


-- Step: Run the validation or aggregation described in the purpose header and return the results.
SELECT *
FROM read_csv_auto('data/vendor_invoice.csv')
LIMIT 10;
