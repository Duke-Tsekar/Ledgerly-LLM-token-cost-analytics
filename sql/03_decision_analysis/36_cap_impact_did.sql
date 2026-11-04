/*
===============================================================================
36 Cap Impact Did
===============================================================================
Purpose:
    - Compare pre/post usage changes for capped tenants against never-treated controls by rollout wave.
    - Count successful retry chains once and present the difference-in-differences estimate as observational evidence, not proof of causality.
===============================================================================
SQL dialect: DuckDB
===============================================================================
*/


WITH RECURSIVE
-- Load the rollout dates and treatment-wave assignments.
rollout AS (
    SELECT
        tenant_id,
        wave,
        CAST(cap_start_date AS DATE) AS cap_start_date
    FROM read_parquet('data/cap_rollout.parquet')
),
--  Load tenant seat counts for per-seat usage metrics.
tenants AS (
    SELECT
        tenant_id,
        CAST(seats AS DOUBLE) AS seats
    FROM read_parquet('data/dim_tenant.parquet')
),
-- Identify the rollout waves and their anchor dates.
cohorts AS (
    SELECT DISTINCT wave, cap_start_date
    FROM rollout
),
-- Build treated and never-treated comparison groups for each rollout wave.
groups AS (
    SELECT
        c.wave AS comparison_wave,
        c.cap_start_date AS anchor_date,
        r.tenant_id,
        'Treated' AS group_type
    FROM cohorts AS c
    JOIN rollout AS r
      ON r.wave = c.wave
     AND r.cap_start_date = c.cap_start_date

    UNION ALL

    SELECT
        c.wave AS comparison_wave,
        c.cap_start_date AS anchor_date,
        t.tenant_id,
        'Never-treated control' AS group_type
    FROM cohorts AS c
    CROSS JOIN tenants AS t
    WHERE NOT EXISTS (
        SELECT 1
        FROM rollout AS r
        WHERE r.tenant_id = t.tenant_id
    )
),
-- Trace retry attempts back to their original root request.
chain_map AS (
    -- Every root starts a chain.
    SELECT
        request_id,
        request_id AS root_request_id
    FROM fact_cost
    WHERE retry_of IS NULL

    UNION ALL

    -- Follow each retry back to its root.
    SELECT
        child.request_id,
        parent.root_request_id
    FROM fact_cost AS child
    JOIN chain_map AS parent
      ON child.retry_of = parent.request_id
),
-- Identify root requests and their tenant, user, and timestamp.
root_requests AS (
    SELECT
        request_id AS root_request_id,
        tenant_id,
        user_id,
        CAST(ts_utc AS TIMESTAMP) AS root_ts
    FROM fact_cost
    WHERE retry_of IS NULL
),
-- Determine whether each request chain contains a successful attempt.
chain_outcomes AS (
    -- A chain succeeds if any attempt in it has status 'ok'.
    SELECT
        cm.root_request_id,
        BOOL_OR(f.status = 'ok') AS chain_succeeded,
        BOOL_OR(f.status = 'ok') AS has_successful_user_activity
    FROM chain_map AS cm
    JOIN fact_cost AS f
      ON f.request_id = cm.request_id
    GROUP BY cm.root_request_id
),
-- Keep successful request chains so retries are not counted as separate successful work.
successful_chains AS (
    SELECT
        rr.root_request_id,
        rr.tenant_id,
        rr.user_id,
        rr.root_ts
    FROM root_requests AS rr
    JOIN chain_outcomes AS co
      ON co.root_request_id = rr.root_request_id
    WHERE co.chain_succeeded
),
-- Create the pre- and post-rollout weekly observation windows.
period_weeks AS (
    SELECT
        g.comparison_wave,
        g.anchor_date,
        g.tenant_id,
        g.group_type,
        w.week_offset,
        CASE WHEN w.week_offset < 0 THEN 'Pre' ELSE 'Post' END AS period,
        CAST(
            g.anchor_date + w.week_offset * INTERVAL '7 days'
            AS DATE
        ) AS week_start
    FROM groups AS g
    CROSS JOIN generate_series(-4, 3) AS w(week_offset)
),
-- Calculate weekly successful request chains and active users for each tenant.
weekly_metrics AS (
    SELECT
        p.comparison_wave,
        p.anchor_date,
        p.tenant_id,
        p.group_type,
        p.period,
        p.week_offset,
        p.week_start,
        t.seats,
        COUNT(sc.root_request_id) AS unique_successful_chains,
        COUNT(DISTINCT sc.user_id) AS weekly_active_users
    FROM period_weeks AS p
    LEFT JOIN tenants AS t
      ON t.tenant_id = p.tenant_id
    LEFT JOIN successful_chains AS sc
      ON sc.tenant_id = p.tenant_id
     AND sc.root_ts >= CAST(p.week_start AS TIMESTAMP)
     AND sc.root_ts < CAST(p.week_start + INTERVAL '7 days' AS TIMESTAMP)
    GROUP BY
        p.comparison_wave,
        p.anchor_date,
        p.tenant_id,
        p.group_type,
        p.period,
        p.week_offset,
        p.week_start,
        t.seats
),
-- Average weekly metrics within each tenant and pre/post period.
tenant_period AS (
    SELECT
        comparison_wave,
        anchor_date,
        tenant_id,
        group_type,
        period,
        AVG(
            CASE
                WHEN seats > 0
                THEN unique_successful_chains / seats
            END
        ) AS requests_per_seat_week,
        AVG(weekly_active_users) AS weekly_active_users
    FROM weekly_metrics
    GROUP BY
        comparison_wave,
        anchor_date,
        tenant_id,
        group_type,
        period
),
-- Aggregate tenant-level metrics for treated and control groups.
group_summary AS (
    SELECT
        comparison_wave,
        anchor_date,
        group_type,
        period,
        COUNT(*) AS tenant_count,
        AVG(requests_per_seat_week) AS requests_per_seat_week,
        AVG(weekly_active_users) AS weekly_active_users
    FROM tenant_period
    GROUP BY
        comparison_wave,
        anchor_date,
        group_type,
        period
),
-- Place pre- and post-period metrics side by side for the final comparison.
pivoted AS (
    SELECT
        comparison_wave,
        anchor_date,
        group_type,
        MAX(tenant_count) AS tenant_count,
        MAX(requests_per_seat_week) FILTER (WHERE period = 'Pre')
            AS pre_requests_per_seat_week,
        MAX(requests_per_seat_week) FILTER (WHERE period = 'Post')
            AS post_requests_per_seat_week,
        MAX(weekly_active_users) FILTER (WHERE period = 'Pre')
            AS pre_weekly_active_users,
        MAX(weekly_active_users) FILTER (WHERE period = 'Post')
            AS post_weekly_active_users
    FROM group_summary
    GROUP BY comparison_wave, anchor_date, group_type
)
SELECT
    comparison_wave AS rollout_wave,
    anchor_date AS rollout_start_date,
    group_type,
    tenant_count,
    ROUND(pre_requests_per_seat_week, 3)
        AS pre_requests_per_seat_week,
    ROUND(post_requests_per_seat_week, 3)
        AS post_requests_per_seat_week,
    ROUND(
        post_requests_per_seat_week - pre_requests_per_seat_week, 3
    ) AS change_requests_per_seat_week,
    ROUND(pre_weekly_active_users, 3) AS pre_weekly_active_users,
    ROUND(post_weekly_active_users, 3) AS post_weekly_active_users,
    ROUND(
        post_weekly_active_users - pre_weekly_active_users, 3
    ) AS change_weekly_active_users
FROM pivoted
ORDER BY rollout_wave, group_type;


/*
The table below shows the difference-in-differences (DiD):
the treated group’s change minus the never-treated group’s change.
Rollout wave	Requests/seat/week DiD	Active users/tenant DiD
Wave 1	−0.844	−2.511
Wave 2	−1.247	−2.427
Wave 3	−1.851	−2.350

All three waves show smaller increases in usage and weekly active users than the never-treated group.
But because the groups started at very different levels, these gaps cannot be confidently attributed to caps.
2. Mariam’s recommendation
Do not roll out caps broadly on this evidence alone. Run a controlled Q1 pilot and compare capped tenants with 
similar uncapped tenants. Track:
- Requests per seat per week
- Weekly active users per tenant
- LLM cost and gross margin
- Customer impact when tenants reach the cap
Set acceptable adoption-decline guardrails before the pilot begins. If customers frequently hit caps while adoption
remains healthy, compare a tiered overage option against a hard cap.
*/