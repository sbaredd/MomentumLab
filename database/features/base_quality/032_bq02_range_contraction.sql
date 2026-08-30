-- ============================================================================
-- MomentumLab
-- Feature     : BQ02 - Post-Low Range Contraction
-- File        : 032_bq02_range_contraction.sql
-- Version     : 2.0
--
-- Purpose:
--   Calculate and persist raw BQ02 Range Contraction features
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

post_low_data AS
(
    SELECT
        c.security_id,
        c.symbol,
        c.base_low_date,

        b.traded_date,
        b.high_price,
        b.low_price,
        b.close_price,

        (
            (b.high_price - b.low_price)
            / NULLIF(b.close_price, 0)
            * 100
        ) AS range_pct,

        ROW_NUMBER() OVER
        (
            PARTITION BY c.security_id
            ORDER BY b.traded_date
        ) AS session_no,

        COUNT(*) OVER
        (
            PARTITION BY c.security_id
        ) AS total_sessions

    FROM current_candidates c

    CROSS JOIN params p

    JOIN trn.nse_sec_bhavdata b
      ON b.symbol = c.symbol
     AND b.series = 'EQ'
     AND b.traded_date > c.base_low_date
     AND b.traded_date <= p.trade_date
),

bq02 AS
(
    SELECT
        security_id,

        COUNT(*) AS post_low_sessions,

        ROUND(
            AVG(range_pct)
            FILTER (WHERE session_no <= 3)::numeric,
            4
        ) AS early_3_avg_range_pct,

        ROUND(
            AVG(range_pct)
            FILTER
            (
                WHERE session_no > total_sessions - 3
            )::numeric,
            4
        ) AS recent_3_avg_range_pct,

        ROUND(
            (
                (
                    AVG(range_pct)
                    FILTER (WHERE session_no <= 3)
                    -
                    AVG(range_pct)
                    FILTER
                    (
                        WHERE session_no > total_sessions - 3
                    )
                )
                /
                NULLIF(
                    AVG(range_pct)
                    FILTER (WHERE session_no <= 3),
                    0
                )
                * 100
            )::numeric,
            4
        ) AS range_contraction_pct

    FROM post_low_data

    GROUP BY security_id
),

resolved AS
(
    SELECT
        q.security_id,
        p.trade_date,

        q.post_low_sessions,
        q.early_3_avg_range_pct,
        q.recent_3_avg_range_pct,
        q.range_contraction_pct

    FROM bq02 q

    CROSS JOIN params p

    WHERE q.post_low_sessions >= 6
)

UPDATE trn.stock_base_quality_daily t

SET
    post_low_sessions =
        r.post_low_sessions,

    early_3_avg_range_pct =
        r.early_3_avg_range_pct,

    recent_3_avg_range_pct =
        r.recent_3_avg_range_pct,

    range_contraction_pct =
        r.range_contraction_pct

FROM resolved r

WHERE t.security_id = r.security_id
  AND t.trade_date  = r.trade_date;