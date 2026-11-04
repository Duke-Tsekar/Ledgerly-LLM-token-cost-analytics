/*
===============================================================================
09 Reconcile Monthly Cost
===============================================================================
Purpose:
    - Aggregate calculated request costs and invoice amounts by month.
    - Quantify monthly and total reconciliation variances.
===============================================================================
SQL dialect: DuckDB
===============================================================================
*/

WITH calculated AS (
    SELECT
        STRFTIME(CAST(ts_utc AS TIMESTAMP), '%Y-%m') AS month,
        SUM(estimated_cost_usd) AS calculated_usd
    FROM read_parquet('data/fact_cost.parquet')
    GROUP BY 1
),

-- Load and aggregate the vendor invoice amounts at the same monthly grain.

invoice AS (
    SELECT
        month,
        invoiced_usd
    FROM read_csv_auto('data/vendor_invoice.csv')
)

SELECT
    i.month,
    ROUND(i.invoiced_usd, 2) AS invoiced_usd,
    ROUND(c.calculated_usd, 2) AS calculated_usd,
    ROUND(c.calculated_usd - i.invoiced_usd, 2) AS variance_usd,
    ROUND(
        100.0 * (c.calculated_usd - i.invoiced_usd)
        / NULLIF(i.invoiced_usd, 0),
        4
    ) AS variance_pct
FROM invoice i
LEFT JOIN calculated c USING (month)
ORDER BY i.month;
