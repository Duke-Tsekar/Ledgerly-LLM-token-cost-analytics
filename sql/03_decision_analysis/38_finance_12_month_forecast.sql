/*
===============================================================================
38 Finance 12 Month Forecast
===============================================================================
Purpose:
    - Project October 2026 to September 2027 list-price usage under alternative growth and optimization assumptions.
    - Compare the annual commitment cost with pay-as-you-go and quantify scenario savings or losses.
===============================================================================
SQL dialect: DuckDB
===============================================================================
*/


WITH baseline AS (
    SELECT SUM(estimated_cost_usd) AS september_list_spend_usd
    FROM fact_cost
    WHERE CAST(ts_utc AS TIMESTAMP) >= TIMESTAMP '2026-09-01 00:00:00'
      AND CAST(ts_utc AS TIMESTAMP) <  TIMESTAMP '2026-10-01 00:00:00'
),
--  Define the monthly growth assumptions for the forecast.
growth_scenarios AS (
    SELECT 'Flat' AS growth_scenario, 0.00 AS monthly_growth_rate
    UNION ALL SELECT 'Low growth', 0.02
    UNION ALL SELECT 'Moderate growth', 0.04
    UNION ALL SELECT 'High growth', 0.06
),
--  Define the usage-reduction assumptions for the forecast.
optimization_scenarios AS (
    SELECT 'No optimization' AS optimization_scenario, 0.00 AS usage_reduction
    UNION ALL SELECT '10% usage reduction', 0.10
    UNION ALL SELECT '30% usage reduction', 0.30
),
--  Generate monthly spend projections for every growth and optimization combination.
monthly_forecast AS (
    SELECT
        g.growth_scenario,
        g.monthly_growth_rate,
        o.optimization_scenario,
        o.usage_reduction,
        b.september_list_spend_usd,
        m.month_number,
        b.september_list_spend_usd
            * POWER(1 + g.monthly_growth_rate, m.month_number)
            * (1 - o.usage_reduction) AS projected_list_usage_usd
    FROM baseline AS b
    CROSS JOIN growth_scenarios AS g
    CROSS JOIN optimization_scenarios AS o
    CROSS JOIN generate_series(1, 12) AS m(month_number)
),
--  Sum the monthly projections to compare annual contract options.
annual_forecast AS (
    SELECT
        growth_scenario,
        monthly_growth_rate,
        optimization_scenario,
        usage_reduction,
        MAX(september_list_spend_usd) AS september_list_spend_usd,
        SUM(projected_list_usage_usd) AS projected_annual_list_usage_usd
    FROM monthly_forecast
    GROUP BY
        growth_scenario,
        monthly_growth_rate,
        optimization_scenario,
        usage_reduction
)
SELECT
    growth_scenario,
    ROUND(monthly_growth_rate * 100, 1) AS assumed_monthly_growth_pct,
    optimization_scenario,
    ROUND(usage_reduction * 100, 1) AS assumed_usage_reduction_pct,
    ROUND(september_list_spend_usd, 2) AS september_list_spend_usd,
    ROUND(projected_annual_list_usage_usd, 2)
        AS projected_annual_list_usage_usd,
    ROUND(projected_annual_list_usage_usd * 0.85, 2)
        AS discounted_usage_cost_usd,
    ROUND(
        GREATEST(360000.00, projected_annual_list_usage_usd * 0.85),
        2
    ) AS annual_cost_with_commit_usd,
    ROUND(projected_annual_list_usage_usd, 2)
        AS annual_cost_without_commit_usd,
    ROUND(
        projected_annual_list_usage_usd
        - GREATEST(360000.00, projected_annual_list_usage_usd * 0.85),
        2
    ) AS savings_from_commit_usd,
    CASE
        WHEN projected_annual_list_usage_usd < 360000
            THEN 'Pay-as-you-go cheaper'
        WHEN projected_annual_list_usage_usd < 360000 / 0.85
            THEN 'Commit cheaper; floor applies'
        ELSE 'Commit cheaper; discounted usage exceeds floor'
    END AS decision_signal
FROM annual_forecast
ORDER BY monthly_growth_rate, usage_reduction;


/*
We now have a clear trade-off for Adaeze: the $360k commitment is attractive under several growth scenarios,
but a 30% usage reduction makes pay-as-you-go cheaper in most low- and moderate-growth cases.
1. Finance decision summary
Best commitment savings shown
+$86,905
6% monthly growth, no optimization

Worst commitment outcome shown
−$87,847
Flat usage, 30% reduction



Growth assumption	Optimization	Savings from commitment
Flat	None	+$28,789
2% monthly	10% reduction	+$38,908
4% monthly	10% reduction	+$68,350
4% monthly	30% reduction	−$5,593
6% monthly	30% reduction	+$45,556

Positive values mean the commitment is cheaper than pay-as-you-go; negative values mean pay-as-you-go is cheaper.

Preliminary recommendation: don’t sign unconditionally. Validate expected usage growth and realistic optimization 
savings first. These are scenarios, not probabilities or a validated forecast.

*/