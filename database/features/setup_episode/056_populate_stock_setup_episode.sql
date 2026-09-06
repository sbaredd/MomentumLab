-- ============================================================================
-- MomentumLab
-- SR09 - Active Pivot Episode Engine
--
-- File:
--   056_populate_stock_setup_episode.sql
--
-- Purpose:
--   Build durable setup episodes from stock_setup_readiness_daily.
--
-- Natural episode identity:
--   security_id + pivot_date + pivot_price + episode_start_date
--
-- Lifecycle:
--   ACTIVE
--   RESOLVED_BREAKOUT
--   SUPERSEDED
--   EXPIRED
--
-- Important:
--   run_id is an internal reconstruction device only.
--   It is NOT persisted as episode identity.
--
-- Parameter:
--   :evaluation_date
-- ============================================================================

WITH pivot_rows AS
(
    SELECT
        security_id,
        trade_date,
        pivot_date,
        pivot_price,
        pivot_type,
        breakout_state,
        pivot_proximity_pct,

        LAG(pivot_date) OVER
        (
            PARTITION BY security_id
            ORDER BY trade_date
        ) AS prev_pivot_date,

        LAG(pivot_price) OVER
        (
            PARTITION BY security_id
            ORDER BY trade_date
        ) AS prev_pivot_price

    FROM trn.stock_setup_readiness_daily

    WHERE trade_date <= CAST(:evaluation_date AS DATE)
      AND pivot_date IS NOT NULL
      AND pivot_price IS NOT NULL
),

run_flags AS
(
    SELECT
        *,

        CASE
            WHEN prev_pivot_date = pivot_date
             AND prev_pivot_price = pivot_price
            THEN 0
            ELSE 1
        END AS new_run

    FROM pivot_rows
),

runs AS
(
    SELECT
        *,

        SUM(new_run) OVER
        (
            PARTITION BY security_id
            ORDER BY trade_date
            ROWS UNBOUNDED PRECEDING
        ) AS run_id

    FROM run_flags
),

episode_runs AS
(
    SELECT
        security_id,
        pivot_date,
        pivot_price,
        run_id,

        MIN(trade_date) AS episode_start_date,
        MAX(trade_date) AS last_observation_date,

        (ARRAY_AGG(pivot_type ORDER BY trade_date))[1]
            AS initial_pivot_type,

        (ARRAY_AGG(pivot_type ORDER BY trade_date DESC))[1]
            AS final_pivot_type,

        COUNT(*) AS observation_count,

        (ARRAY_AGG(pivot_proximity_pct ORDER BY trade_date))[1]
            AS start_proximity_pct,

        MIN(pivot_proximity_pct)
            AS min_proximity_pct,

        MAX(pivot_proximity_pct)
            AS max_proximity_pct,

        (ARRAY_AGG(pivot_proximity_pct ORDER BY trade_date DESC))[1]
            AS end_proximity_pct,

        MAX(trade_date) FILTER
        (
            WHERE breakout_state = 'CROSSED_AND_CLOSED_ABOVE'
        ) AS breakout_date,

        (ARRAY_AGG(breakout_state ORDER BY trade_date DESC))[1]
            AS terminal_breakout_state

    FROM runs

    GROUP BY
        security_id,
        pivot_date,
        pivot_price,
        run_id
),

classified AS
(
    SELECT
        e.*,

        CASE
            WHEN breakout_date IS NOT NULL
                THEN 'RESOLVED_BREAKOUT'

            WHEN last_observation_date = CAST(:evaluation_date AS DATE)
                THEN 'ACTIVE'

            WHEN EXISTS
            (
                SELECT 1
                FROM runs r2
                WHERE r2.security_id = e.security_id
                  AND r2.trade_date > e.last_observation_date
            )
                THEN 'SUPERSEDED'

            ELSE 'EXPIRED'
        END AS episode_status

    FROM episode_runs e
)

INSERT INTO trn.stock_setup_episode
(
    security_id,
    pivot_date,
    pivot_price,
    episode_start_date,
    episode_end_date,

    initial_pivot_type,
    final_pivot_type,

    observation_count,

    start_proximity_pct,
    min_proximity_pct,
    max_proximity_pct,
    end_proximity_pct,

    episode_status,

    breakout_date,
    terminal_breakout_state,

    updated_date
)

SELECT
    security_id,
    pivot_date,
    pivot_price,
    episode_start_date,

    CASE
        WHEN episode_status = 'ACTIVE'
            THEN NULL
        ELSE last_observation_date
    END AS episode_end_date,

    initial_pivot_type,
    final_pivot_type,

    observation_count,

    start_proximity_pct,
    min_proximity_pct,
    max_proximity_pct,
    end_proximity_pct,

    episode_status,

    CASE
        WHEN episode_status = 'RESOLVED_BREAKOUT'
            THEN breakout_date
        ELSE NULL
    END AS breakout_date,

    CASE
        WHEN episode_status = 'RESOLVED_BREAKOUT'
            THEN terminal_breakout_state
        ELSE NULL
    END AS terminal_breakout_state,

    CURRENT_TIMESTAMP

FROM classified

ON CONFLICT
(
    security_id,
    pivot_date,
    pivot_price,
    episode_start_date
)

DO UPDATE SET

    episode_end_date =
        EXCLUDED.episode_end_date,

    final_pivot_type =
        EXCLUDED.final_pivot_type,

    observation_count =
        EXCLUDED.observation_count,

    start_proximity_pct =
        EXCLUDED.start_proximity_pct,

    min_proximity_pct =
        EXCLUDED.min_proximity_pct,

    max_proximity_pct =
        EXCLUDED.max_proximity_pct,

    end_proximity_pct =
        EXCLUDED.end_proximity_pct,

    episode_status =
        EXCLUDED.episode_status,

    breakout_date =
        EXCLUDED.breakout_date,

    terminal_breakout_state =
        EXCLUDED.terminal_breakout_state,

    updated_date =
        CURRENT_TIMESTAMP;
    
