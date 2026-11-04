/*
===============================================================================
27 Cap Pre-Trend Check
===============================================================================
Purpose:
    - Check pre-rollout trends for the cap evaluation.
    - Business use: Assess whether a causal cap-impact estimate is credible.
===============================================================================
SQL dialect: DuckDB
===============================================================================
*/

WITH weekly AS (
    SELECT
        DATE_TRUNC('week', CAST(r.ts_utc AS TIMESTAMP)) AS week_start,
        r.tenant_id,
        COUNT(*) * 1.0 / NULLIF(t.seats, 0) AS requests_per_seat,
        COUNT(DISTINCT r.user_id) FILTER (
            WHERE r.status = 'ok'
        ) AS weekly_active_users
    FROM fact_cost r
    JOIN read_parquet('data/dim_feature.parquet') f
        ON r.feature_id = f.feature_id
    JOIN read_parquet('data/dim_tenant.parquet') t
        ON r.tenant_id = t.tenant_id
    WHERE f.feature_id = 'support_copilot'
      AND CAST(r.ts_utc AS TIMESTAMP)
          >= TIMESTAMP '2026-07-06'
      AND CAST(r.ts_utc AS TIMESTAMP)
          < TIMESTAMP '2026-08-24'
    GROUP BY 1, 2, t.seats
),
-- Load the rollout dates and treatment-wave assignments.
rollout AS (
    SELECT
        tenant_id,
        wave,
        CAST(cap_start_date AS TIMESTAMP) AS cap_start_date
    FROM read_parquet('data/cap_rollout.parquet')
)
SELECT
    w.week_start,
    r.wave,
    COUNT(DISTINCT w.tenant_id) AS tenants,
    ROUND(AVG(w.requests_per_seat), 3) AS avg_requests_per_seat,
    ROUND(AVG(w.weekly_active_users), 2) AS avg_weekly_active_users
FROM weekly w
JOIN rollout r ON w.tenant_id = r.tenant_id
WHERE w.week_start < DATE_TRUNC('week', r.cap_start_date)
GROUP BY 1, 2
ORDER BY 1, 2;
