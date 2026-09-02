-- ============================================================================
-- MomentumLab
-- Base Quality Diagnostic
-- BQ07 - Energy Stored
--
-- Purpose:
--   Examine whether the latter part of the base is becoming quieter
--   than the earlier part.
--
-- Diagnostic dimensions:
--   1. Range compression
--   2. Volume contraction
--   3. Recent vs early volatility behaviour
--
-- Test universe:
--   5PAISA, CHENNPETRO, DEEPINDS, KTKBANK
--
-- As-of date:
--   2026-08-13
--
-- IMPORTANT:
--   - Diagnostic research only
--   - No scoring
--   - No production UPDATE
-- ============================================================================

WITH candidates AS
(
    SELECT
        q.security_id,
        s.symbol,
        q.trade_date,
        q.base_low_date,
        q.post_low_sessions

    FROM trn.stock_base_quality_daily q

    JOIN ref.ref_nse_equity_security s
      ON s.security_id = q.security_id

    WHERE q.trade_date = DATE '2026-08-13'
      AND s.symbol IN
          ('5PAISA', 'CHENNPETRO', 'DEEPINDS', 'KTKBANK')
),

post_low_data AS
(
    SELECT
        c.security_id,
        c.symbol,
        c.trade_date,
        c.base_low_date,

        b.traded_date,
        b.high_price,
        b.low_price,
        b.close_price,
        b.traded_quantity,

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

    FROM candidates c

    JOIN trn.nse_sec_bhavdata b
      ON b.symbol = c.symbol
     AND b.series = 'EQ'
     AND b.traded_date > c.base_low_date
     AND b.traded_date <= c.trade_date
),

classified AS
(
    SELECT
        *,

        CASE
            WHEN session_no <= 3
            THEN 'EARLY'

            WHEN session_no > total_sessions - 3
            THEN 'RECENT'

            ELSE 'MIDDLE'
        END AS base_phase

    FROM post_low_data
),

summary AS
(
    SELECT
        symbol,
        COUNT(*) AS post_low_sessions,

        ROUND(
            AVG(range_pct)
            FILTER (WHERE base_phase = 'EARLY')::numeric,
            4
        ) AS early_3_avg_range_pct,

        ROUND(
            AVG(range_pct)
            FILTER (WHERE base_phase = 'RECENT')::numeric,
            4
        ) AS recent_3_avg_range_pct,

        ROUND(
            (
                (
                    AVG(range_pct)
                    FILTER (WHERE base_phase = 'EARLY')
                    -
                    AVG(range_pct)
                    FILTER (WHERE base_phase = 'RECENT')
                )
                /
                NULLIF(
                    AVG(range_pct)
                    FILTER (WHERE base_phase = 'EARLY'),
                    0
                )
                * 100
            )::numeric,
            4
        ) AS range_compression_pct,

        ROUND(
            AVG(traded_quantity)
            FILTER (WHERE base_phase = 'EARLY')::numeric,
            2
        ) AS early_3_avg_volume,

        ROUND(
            AVG(traded_quantity)
            FILTER (WHERE base_phase = 'RECENT')::numeric,
            2
        ) AS recent_3_avg_volume,

        ROUND(
            (
                (
                    AVG(traded_quantity)
                    FILTER (WHERE base_phase = 'EARLY')
                    -
                    AVG(traded_quantity)
                    FILTER (WHERE base_phase = 'RECENT')
                )
                /
                NULLIF(
                    AVG(traded_quantity)
                    FILTER (WHERE base_phase = 'EARLY'),
                    0
                )
                * 100
            )::numeric,
            4
        ) AS volume_contraction_pct

    FROM classified

    GROUP BY symbol
)

SELECT
    symbol,
    post_low_sessions,

    early_3_avg_range_pct,
    recent_3_avg_range_pct,
    range_compression_pct,

    early_3_avg_volume,
    recent_3_avg_volume,
    volume_contraction_pct

FROM summary

ORDER BY symbol;