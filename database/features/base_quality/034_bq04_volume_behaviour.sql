-- ============================================================================
-- MomentumLab
-- Feature     : BQ04 - Post-Low Volume Behaviour
-- File        : 034_bq04_volume_behaviour.sql
-- Version     : 2.0
--
-- Purpose:
--   Calculate and persist raw BQ04 post-low volume-behaviour features
--   for the selected Base Episode universe.
--
-- Input:
--   trn.stock_base_episode_daily
--
-- Production scope:
--   NIFTY_100
--   Selected trade date
--
-- IMPORTANT:
--   - Raw features only
--   - No scoring
--   - Requires at least 6 post-low sessions
--   - Base-low session is reference-only for LAG()
-- ============================================================================

WITH params AS
(
    SELECT
        DATE '2026-08-13' AS trade_date,
        'NIFTY_100'::varchar AS universe_code
),

current_candidates AS
(
    SELECT
        b.security_id,
        s.symbol,
        b.prior_swing_high_date,
        b.prior_swing_high,
        b.base_low_date,
        b.base_low
    FROM trn.stock_base_episode_daily b
    JOIN ref.ref_nse_equity_security s
      ON s.security_id = b.security_id
    JOIN ref.security_universe_membership um
      ON um.security_id = b.security_id
    CROSS JOIN params p
    WHERE b.trade_date = p.trade_date
      AND um.universe_code = p.universe_code
),

post_low_with_anchor AS
(
    SELECT
        c.security_id,
        c.symbol,
        c.base_low_date,

        b.traded_date,
        b.close_price,
        b.traded_quantity,

        LAG(b.close_price) OVER
        (
            PARTITION BY c.security_id
            ORDER BY b.traded_date
        ) AS prev_close

    FROM current_candidates c
    CROSS JOIN params p
    JOIN trn.nse_sec_bhavdata b
      ON b.symbol = c.symbol
     AND b.series = 'EQ'
     AND b.traded_date >= c.base_low_date
     AND b.traded_date <= p.trade_date
),

classified AS
(
    SELECT
        security_id,
        symbol,
        base_low_date,
        traded_date,
        close_price,
        traded_quantity,

        CASE
            WHEN close_price > prev_close THEN 'UP'
            WHEN close_price < prev_close THEN 'DOWN'
            ELSE 'FLAT'
        END AS day_direction

    FROM post_low_with_anchor
    WHERE traded_date > base_low_date
),

bq04 AS
(
    SELECT
        security_id,

        COUNT(*) AS post_low_sessions,

        COUNT(*) FILTER
        (
            WHERE day_direction = 'UP'
        ) AS post_low_up_days,

        COUNT(*) FILTER
        (
            WHERE day_direction = 'DOWN'
        ) AS post_low_down_days,

        COUNT(*) FILTER
        (
            WHERE day_direction = 'FLAT'
        ) AS post_low_flat_days,

        ROUND(
            AVG(traded_quantity)
            FILTER (WHERE day_direction = 'UP')::numeric,
            2
        ) AS avg_up_volume,

        ROUND(
            AVG(traded_quantity)
            FILTER (WHERE day_direction = 'DOWN')::numeric,
            2
        ) AS avg_down_volume,

        ROUND(
            (
                AVG(traded_quantity)
                FILTER (WHERE day_direction = 'DOWN')
                /
                NULLIF(
                    AVG(traded_quantity)
                    FILTER (WHERE day_direction = 'UP'),
                    0
                )
            )::numeric,
            4
        ) AS down_vs_up_volume_ratio,

        ROUND(
            (
                AVG(traded_quantity)
                FILTER (WHERE day_direction = 'UP')
                /
                NULLIF(
                    AVG(traded_quantity)
                    FILTER (WHERE day_direction = 'DOWN'),
                    0
                )
            )::numeric,
            4
        ) AS up_vs_down_volume_ratio

    FROM classified
    GROUP BY security_id
),

resolved AS
(
    SELECT
        q.security_id,
        p.trade_date,
        q.post_low_sessions,
        q.post_low_up_days,
        q.post_low_down_days,
        q.post_low_flat_days,
        q.avg_up_volume,
        q.avg_down_volume,
        q.down_vs_up_volume_ratio,
        q.up_vs_down_volume_ratio

    FROM bq04 q
    CROSS JOIN params p

    WHERE q.post_low_sessions >= 6
)

UPDATE trn.stock_base_quality_daily t
SET
    post_low_sessions =
        r.post_low_sessions,

    post_low_up_days =
        r.post_low_up_days,

    post_low_down_days =
        r.post_low_down_days,

    post_low_flat_days =
        r.post_low_flat_days,

    avg_up_volume =
        r.avg_up_volume,

    avg_down_volume =
        r.avg_down_volume,

    down_vs_up_volume_ratio =
        r.down_vs_up_volume_ratio,

    up_vs_down_volume_ratio =
        r.up_vs_down_volume_ratio

FROM resolved r

WHERE t.security_id = r.security_id
  AND t.trade_date  = r.trade_date;