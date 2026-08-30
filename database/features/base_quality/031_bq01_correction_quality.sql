-- ============================================================================
-- MomentumLab
-- Feature     : BQ01 - Correction Quality
-- File        : 031_bq01_correction_quality.sql
-- Version     : 1.0
--
-- Purpose:
--   Calculate and persist raw BQ01 Correction Quality features for the
--   selected base episode.
--
-- V1 Test Scope:
--   Uses four previously validated base candidates.
--   trade_date = 2026-08-13
--
-- IMPORTANT:
--   - Raw features only
--   - No scoring
--   - NULL means insufficient comparison data
-- ============================================================================

WITH params AS
(
    SELECT DATE '2026-08-13' AS trade_date
),

current_candidates AS
(
    SELECT
        s.symbol,
        b.prior_swing_high_date,
        b.prior_swing_high, 
        b.base_low_date,
        b.base_low

    FROM trn.stock_base_episode_daily b

    JOIN ref.ref_nse_equity_security s
      ON s.security_id = b.security_id

    CROSS JOIN params p

    WHERE b.trade_date = p.trade_date
),

-- --------------------------------------------------------------------------
-- Include the swing-high session so LAG() has the correct reference close.
-- --------------------------------------------------------------------------
price_data AS
(
    SELECT
        c.symbol,
        c.prior_swing_high_date,
        c.prior_swing_high,
        c.base_low_date,
        c.base_low,

        b.traded_date,
        b.high_price,
        b.low_price,
        b.close_price,
        b.traded_quantity,

        LAG(b.close_price) OVER
        (
            PARTITION BY c.symbol
            ORDER BY b.traded_date
        ) AS prev_close

    FROM current_candidates c

    JOIN trn.nse_sec_bhavdata b
      ON b.symbol = c.symbol
     AND b.series = 'EQ'
     AND b.traded_date BETWEEN c.prior_swing_high_date
                           AND c.base_low_date
),

-- --------------------------------------------------------------------------
-- Actual pullback begins AFTER the prior swing-high session.
-- --------------------------------------------------------------------------
pullback_data AS
(
    SELECT
        *,

        (
            (high_price - low_price)
            / NULLIF(close_price, 0)
            * 100
        ) AS range_pct,

        CASE
            WHEN close_price < prev_close THEN 'DOWN'
            WHEN close_price > prev_close THEN 'UP'
            ELSE 'FLAT'
        END AS day_direction

    FROM price_data

    WHERE traded_date > prior_swing_high_date
),

bq01 AS
(
    SELECT
        symbol,

        MAX(prior_swing_high_date) AS prior_swing_high_date,
        MAX(prior_swing_high)      AS prior_swing_high,

        MAX(base_low_date)         AS base_low_date,
        MAX(base_low)              AS base_low,

        ROUND(
            (
                (MAX(prior_swing_high) - MAX(base_low))
                / NULLIF(MAX(prior_swing_high), 0)
                * 100
            )::numeric,
            4
        ) AS correction_depth_pct,

        COUNT(*) AS pullback_sessions,

        ROUND(
            (
                (
                    (MAX(prior_swing_high) - MAX(base_low))
                    / NULLIF(MAX(prior_swing_high), 0)
                    * 100
                )
                / NULLIF(COUNT(*), 0)
            )::numeric,
            4
        ) AS correction_speed_pct_per_session,

        ROUND(
            AVG(range_pct)::numeric,
            4
        ) AS pullback_avg_range_pct,

        ROUND(
            MAX(range_pct)::numeric,
            4
        ) AS pullback_max_range_pct,

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
        ) AS pullback_down_up_volume_ratio

    FROM pullback_data

    GROUP BY symbol
),

resolved AS
(
    SELECT
        s.security_id,
        p.trade_date,
        q.*

    FROM bq01 q

    JOIN ref.ref_nse_equity_security s
      ON s.symbol = q.symbol

    CROSS JOIN params p
)

INSERT INTO trn.stock_base_quality_daily
(
    security_id,
    trade_date,

    prior_swing_high_date,
    prior_swing_high,
    base_low_date,
    base_low,

    correction_depth_pct,
    pullback_sessions,
    correction_speed_pct_per_session,
    pullback_avg_range_pct,
    pullback_max_range_pct,
    pullback_down_up_volume_ratio
)

SELECT
    security_id,
    trade_date,

    prior_swing_high_date,
    prior_swing_high,
    base_low_date,
    base_low,

    correction_depth_pct,
    pullback_sessions,
    correction_speed_pct_per_session,
    pullback_avg_range_pct,
    pullback_max_range_pct,
    pullback_down_up_volume_ratio

FROM resolved

ON CONFLICT (security_id, trade_date)

DO UPDATE SET

    prior_swing_high_date =
        EXCLUDED.prior_swing_high_date,

    prior_swing_high =
        EXCLUDED.prior_swing_high,

    base_low_date =
        EXCLUDED.base_low_date,

    base_low =
        EXCLUDED.base_low,

    correction_depth_pct =
        EXCLUDED.correction_depth_pct,

    pullback_sessions =
        EXCLUDED.pullback_sessions,

    correction_speed_pct_per_session =
        EXCLUDED.correction_speed_pct_per_session,

    pullback_avg_range_pct =
        EXCLUDED.pullback_avg_range_pct,

    pullback_max_range_pct =
        EXCLUDED.pullback_max_range_pct,

    pullback_down_up_volume_ratio =
        EXCLUDED.pullback_down_up_volume_ratio;