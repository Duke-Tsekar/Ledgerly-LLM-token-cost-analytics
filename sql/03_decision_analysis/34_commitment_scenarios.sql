/*
===============================================================================
34 Commitment Scenarios
===============================================================================
Purpose:
    
    - Compare the $360,000 commitment with paying list price as used.
    - Show when the commitment is cheaper and when its minimum spend creates downside risk.
===============================================================================
SQL dialect: DuckDB
===============================================================================
*/

-- Positive net_savings_from_commit_usd means the commitment is cheaper.
-- Negative means the commitment costs more.
-- Growth and optimization rates are scenarios, not forecasts.

WITH september_baseline AS (
    SELECT
        SUM(estimated_cost_usd) AS september_list_spend_usd
    FROM fact_cost
    WHERE CAST(ts_utc AS TIMESTAMP) >= TIMESTAMP '2026-09-01 00:00:00'
      AND CAST(ts_utc AS TIMESTAMP) <  TIMESTAMP '2026-10-01 00:00:00'
),
-- Define the monthly growth assumptions for the forecast.
growth_scenarios AS (
    SELECT 'Flat' AS growth_scenario, 0.00 AS monthly_growth_rate
    UNION ALL
    SELECT 'Low growth', 0.02
    UNION ALL
    SELECT 'Moderate growth', 0.04
    UNION ALL
    SELECT 'High growth', 0.06
),
--  Define the usage-reduction assumptions for the forecast.
optimization_scenarios AS (
    SELECT 'No optimization' AS optimization_scenario, 0.00 AS usage_reduction
    UNION ALL
    SELECT '10% usage reduction', 0.10
    UNION ALL
    SELECT '30% usage reduction', 0.30
),
-- Project monthly usage across the specified growth and optimization scenarios.
monthly_projection AS (
    SELECT
        g.growth_scenario,
        g.monthly_growth_rate,
        o.optimization_scenario,
        o.usage_reduction,
        b.september_list_spend_usd,
        month_number,
        b.september_list_spend_usd
            * POWER(1 + g.monthly_growth_rate, month_number)
            * (1 - o.usage_reduction) AS projected_list_spend_usd
    FROM september_baseline AS b
    CROSS JOIN growth_scenarios AS g
    CROSS JOIN optimization_scenarios AS o
    CROSS JOIN generate_series(0, 11) AS months(month_number)
),
--  Aggregate monthly projections into annual usage for each scenario.
annual_projection AS (
    SELECT
        growth_scenario,
        monthly_growth_rate,
        optimization_scenario,
        usage_reduction,
        MAX(september_list_spend_usd) AS september_list_spend_usd,
        SUM(projected_list_spend_usd) AS annual_list_usage_usd
    FROM monthly_projection
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
    ROUND(annual_list_usage_usd, 2) AS projected_annual_list_usage_usd,
    ROUND(annual_list_usage_usd * 0.85, 2)
        AS projected_usage_cost_with_discount_usd,
    ROUND(
        GREATEST(360000.00, annual_list_usage_usd * 0.85),
        2
    ) AS annual_cost_with_commit_usd,
    ROUND(annual_list_usage_usd, 2)
        AS annual_cost_without_commit_usd,
    ROUND(
        annual_list_usage_usd
        - GREATEST(360000.00, annual_list_usage_usd * 0.85),
        2
    ) AS net_savings_from_commit_usd,
    CASE
        WHEN annual_list_usage_usd < 360000.00
            THEN 'Below $360k list-price break-even'
        WHEN annual_list_usage_usd * 0.85 < 360000.00
            THEN 'Discounted usage below commitment floor'
        ELSE 'Discounted usage exceeds commitment floor'
    END AS commitment_assessment
FROM annual_projection
ORDER BY
    monthly_growth_rate,
    usage_reduction;



/*
These results give us a clear first read for Adaeze, VP Finance:
the $360,000 commitment is attractive under moderate growth with no optimization,
but it becomes a liability under strong optimization unless growth offsets the reduction.
1. The decision in numbers
Best shown scenario
+$81,986
6% monthly growth, no optimization

Worst shown scenario
−$87,847
Flat usage, 30% reduction



Scenario	Commit vs. no commit
Flat usage, no optimization	+$28,789
2% monthly growth, no optimization	+$65,181
4% monthly growth, 10% reduction	+$65,721
4% monthly growth, 30% reduction	−$19,224
6% monthly growth, 30% reduction	+$22,600

Positive means the commitment is cheaper; negative means paying list price as used is cheaper.
2. What Finance should conclude
- The floor is the main risk. Savings from caching and routing can reduce usage below the level
 needed to benefit from the commitment.
- Growth can offset optimization. At 6% monthly growth, even the 30% usage-reduction scenario still
 favors the commitment by about $22,600.
- Do not treat the 6% growth case as a forecast. It is a sensitivity assumption, not a validated prediction.
 These scenarios compound growth from September’s spend for 12 months and use only six months of historical data.
One important correction: the commitment_assessment label “Below $360k list-price break-even” is based on annual 
list usage below $360,000. That is a useful indicator, but the actual decision should use the calculated 
net_savings_from_commit_usd column, which compares the two payment options directly.
*/