/*
===============================================================================
33 Cache Savings Scenarios
===============================================================================
Purpose:
    - Estimate conservative, middle, and high cache-savings scenarios.
    - Translate the opportunity into illustrative six-month savings scenarios 
    (Apr-Sep 2026)
===============================================================================
SQL dialect: DuckDB
===============================================================================
*/

WITH assumptions AS (
    SELECT
        38990.00 AS six_month_theoretical_savings_usd,
        27215.93 AS recent_monthly_spend_usd,
        360000.00 AS proposed_annual_commitment_usd,
        0.15 AS vendor_discount_rate
),
-- Apply the capture assumptions to the theoretical opportunity to estimate savings scenarios.
scenarios AS (
    SELECT 'Conservative' AS scenario, 0.10 AS capture_rate
    UNION ALL
    SELECT 'Middle', 0.25
    UNION ALL
    SELECT 'High', 0.40
),
-- Prepare the calculations intermediate result for the next analysis step.
calculations AS (
    SELECT
        s.scenario,
        s.capture_rate,
        a.six_month_theoretical_savings_usd,
        a.recent_monthly_spend_usd,
        a.proposed_annual_commitment_usd,
        a.vendor_discount_rate,
        a.six_month_theoretical_savings_usd
            * s.capture_rate AS six_month_estimated_savings_usd,
        a.six_month_theoretical_savings_usd
            * s.capture_rate / 6.0 AS monthly_estimated_savings_usd
    FROM scenarios AS s
    CROSS JOIN assumptions AS a
)
SELECT
    scenario,
    capture_rate * 100 AS assumed_capture_pct,
    ROUND(six_month_theoretical_savings_usd, 2)
        AS six_month_theoretical_opportunity_usd,
    ROUND(six_month_estimated_savings_usd, 2)
        AS estimated_six_month_savings_usd,
    ROUND(monthly_estimated_savings_usd, 2)
        AS estimated_monthly_savings_usd,
    ROUND(
        recent_monthly_spend_usd - monthly_estimated_savings_usd,
        2
    ) AS adjusted_monthly_spend_usd,
    ROUND(
        (recent_monthly_spend_usd - monthly_estimated_savings_usd) * 12,
        2
    ) AS adjusted_annualized_spend_usd,
    ROUND(
        proposed_annual_commitment_usd
        - (recent_monthly_spend_usd - monthly_estimated_savings_usd)
            * 12 * (1 - vendor_discount_rate),
        2
    ) AS commitment_above_discounted_annualized_spend_usd
FROM calculations
ORDER BY capture_rate;




-- The $38,990 opportunity is the theoretical Apr-Sep 2026
-- candidate savings identified in SQL 32, not guaranteed savings.