/*
===============================================================================
35 Commitment Break Even Growth
===============================================================================
Purpose:
    - Find the minimum monthly usage growth needed for the commitment to cost no more than pay-as-you-go.
    - Show how the break-even point changes under different usage-reduction assumptions.
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
-- Define the usage-reduction assumptions to test.
optimizations AS (
    SELECT 'No optimization' AS scenario, 0.00 AS reduction
    UNION ALL
    SELECT '10% usage reduction', 0.10
    UNION ALL
    SELECT '30% usage reduction', 0.30
),
--  Project annual usage across a range of monthly growth assumptions.
growth_grid AS (
    SELECT
        o.scenario,
        o.reduction,
        b.september_list_spend_usd,
        g.monthly_growth_rate,
        SUM(
            b.september_list_spend_usd
            * POWER(1 + g.monthly_growth_rate, months.month_number)
            * (1 - o.reduction)
        ) AS annual_list_usage_usd
    FROM baseline AS b
    CROSS JOIN optimizations AS o
    CROSS JOIN (
        SELECT range / 1000.0 AS monthly_growth_rate
        FROM range(0, 151)
    ) AS g
    CROSS JOIN generate_series(0, 11) AS months(month_number)
    GROUP BY
        o.scenario,
        o.reduction,
        b.september_list_spend_usd,
        g.monthly_growth_rate
),
-- Calculate the annual cost under pay-as-you-go and the commitment terms.
evaluated AS (
    SELECT
        *,
        GREATEST(360000.00, annual_list_usage_usd * 0.85)
            AS annual_cost_with_commit_usd,
        annual_list_usage_usd AS annual_cost_without_commit_usd
    FROM growth_grid
),
-- Find the lowest tested growth rate at which the commitment is no more expensive.
break_even AS (
    SELECT
        scenario,
        reduction,
        MIN(monthly_growth_rate) FILTER (
            WHERE annual_cost_with_commit_usd
                  <= annual_cost_without_commit_usd
        ) AS break_even_monthly_growth_rate
    FROM evaluated
    GROUP BY scenario, reduction
)
SELECT
    scenario AS optimization_scenario,
    ROUND(reduction * 100, 1) AS usage_reduction_pct,
    ROUND(break_even_monthly_growth_rate * 100, 1)
        AS minimum_monthly_growth_pct,
    ROUND(
        (POWER(1 + break_even_monthly_growth_rate, 12) - 1) * 100,
        1
    ) AS approximate_12_month_compounded_growth_pct
FROM break_even
ORDER BY reduction;

/*

What the results mean
Usage scenario	Minimum monthly growth	Finance implication
No optimization	0%	The commitment is already cheaper in this model because discounted usage exceeds the floor.
10% usage reduction	0.6%	Only modest growth is needed to break even.
30% usage reduction	5.0%	The commitment depends heavily on continued growth.

One nuance: the last column is the compounded increase from the first projected month to the twelfth,
not a separate forecast. Also, the break-even rates are based on a grid in 0.1-percentage-point increments, 
so treat them as approximate.
Preliminary recommendation for Adaeze
Do not recommend signing unconditionally. The commitment looks favorable if growth continues and optimization
is modest, but risky if caching and routing materially reduce usage. The next step is to compare these 
assumptions with actual observed growth and decide which scenario is credible.

We’ve now got the core contract sensitivity. I suggest we move to the other urgent decision:
Mariam’s Q1 usage-cap/pricing decision—specifically, whether the existing rollout evidence is strong enough 
to justify broad caps or whether a controlled pilot is safer.
*/