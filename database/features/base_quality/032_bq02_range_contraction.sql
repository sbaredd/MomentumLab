-- ============================================================================
-- MomentumLab
-- Feature     : BQ02 - Post-Low Range Contraction
-- File        : 032_bq02_range_contraction.sql
-- Version     : 1.0
--
-- Purpose:
--   Calculate and persist raw BQ02 Base Tightness features for the
--   selected base episode.
--
-- V1 Test Scope:
--   Uses four previously validated base candidates.
--   trade_date = 2026-08-13
--
-- IMPORTANT:
--   - Raw features only
--   - No scoring
--   - Requires at least 6 post-low sessions
-- ============================================================================

WITH params AS
(
    SELECT DATE '2026-08-13' AS trade_date
),

current_candidates
(
    symbol,
    prior_swing_high_date,
    prior_swing_high,
    base_low_date,
    base_low
) AS
(
    VALUES
        ('5PAISA',     DATE '2026-07-27', 381.95::numeric,
                       DATE '2026-07-30', 344.00::numeric),

        ('CHENNPETRO', DATE '2026-07-23', 1354.00::numeric,
                       DATE '2026-07-28', 1150.00::numeric),

        ('DEEPINDS',   DATE '2026-07-20', 487.00::numeric,
                       DATE '2026-07-24', 453.60::numeric),

        ('KTKBANK',    DATE '2026-07-15', 280.00::numeric,
                       DATE '2026-07-17', 268.35::numeric)
),

post_low_data AS
(
    SELECT
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
            PARTITION BY c.symbol
            ORDER BY b.traded_date
        ) AS session_no,

        COUNT(*) OVER
        (
            PARTITION BY c.symbol
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
        symbol,

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

    GROUP BY symbol
),

resolved AS
(
    SELECT
        s.security_id,
        p.trade_date,
        q.*

    FROM bq02 q

    JOIN ref.ref_nse_equity_security s
      ON s.symbol = q.symbol

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
  AND t.trade_date = r.trade_date;