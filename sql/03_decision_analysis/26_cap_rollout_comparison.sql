/*
===============================================================================
26 Cap Rollout Comparison
===============================================================================
Purpose:
    - Compare capped and not-yet-capped tenants by week.
    - Business use: Assess usage-cap impact while monitoring adoption.
    - Describe how usage changed around the rollout without claiming a causal effect.
===============================================================================
SQL dialect: DuckDB
===============================================================================
*/


WITH weekly AS (
    SELECT
        DATE_TRUNC('week', CAST(r.ts_utc AS TIMESTAMP)) AS week_start,
        r.tenant_id,
        COUNT(*) AS request_attempts,
        COUNT(DISTINCT r.user_id) FILTER (
            WHERE r.status = 'ok'
        ) AS weekly_active_users
    FROM fact_cost r
    JOIN read_parquet('data/dim_feature.parquet') f
        ON r.feature_id = f.feature_id
    WHERE f.feature_id = 'support_copilot'
    GROUP BY 1, 2
),
-- Step: Load the rollout dates and treatment-wave assignments.
rollout AS (
    SELECT
        tenant_id,
        CAST(cap_start_date AS TIMESTAMP) AS cap_start_date,
        wave
    FROM read_parquet('data/cap_rollout.parquet')
),
-- Step: Prepare the panel intermediate result for the next analysis step.
panel AS (
    SELECT
        w.week_start,
        w.tenant_id,
        w.request_attempts * 1.0 / NULLIF(t.seats, 0)
            AS requests_per_seat,
        w.weekly_active_users,
        r.wave,
        r.cap_start_date,
        CASE
            WHEN r.tenant_id IS NULL THEN 'never_in_rollout'
            WHEN w.week_start < DATE_TRUNC('week', r.cap_start_date)
                THEN 'not_yet_treated'
            ELSE 'treated'
        END AS treatment_status
    FROM weekly w
    JOIN read_parquet('data/dim_tenant.parquet') t
        ON w.tenant_id = t.tenant_id
    LEFT JOIN rollout r
        ON w.tenant_id = r.tenant_id
    WHERE w.week_start BETWEEN TIMESTAMP '2026-07-06'
                           AND TIMESTAMP '2026-09-28'
)
SELECT
    week_start,
    treatment_status,
    wave,
    COUNT(DISTINCT tenant_id) AS tenants,
    ROUND(AVG(requests_per_seat), 3) AS avg_requests_per_seat,
    ROUND(AVG(weekly_active_users), 2) AS avg_weekly_active_users
FROM panel
GROUP BY 1, 2, 3
ORDER BY 1, 2, 3;
