-- ============================================================================
-- MomentumLab
-- Feature     : BQ05 - Selling Pressure
-- File        : 035_bq05_selling_pressure.sql
-- Version     : 1.0
--
-- Purpose:
--   Measure how damaging selling is after the base low.
--
-- V1 Validation Scope:
--   5PAISA, CHENNPETRO, DEEPINDS, KTKBANK
--   as-of date = 2026-08-13
--
-- Important:
--   - Base-low session is reference-only for previous close.
--   - 20-session average volume is calculated using history BEFORE
--     filtering to the post-low period.
--   - Raw features only. No scoring.
-- ============================================================================

WITH candidates AS
(
    SELECT
        q.security_id,
        s.symbol,
        q.trade_date,
        q.base_low_date

    FROM trn.stock_base_quality_daily q

    JOIN ref.ref_nse_equity_security s
      ON s.security_id = q.security_id

    WHERE q.trade_date = DATE '2026-08-13'
      AND s.symbol IN
          ('5PAISA', 'CHENNPETRO', 'DEEPINDS', 'KTKBANK')
),

-- ============================================================================
-- Build sufficient historical data FIRST.
-- This allows LAG() and AVG(volume,20) to use proper history.
-- ============================================================================

history AS
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

        LAG(b.close_price) OVER
        (
            PARTITION BY c.security_id
            ORDER BY b.traded_date
        ) AS prev_close,

        AVG(b.traded_quantity) OVER
        (
            PARTITION BY c.security_id
            ORDER BY b.traded_date
            ROWS BETWEEN 19 PRECEDING AND CURRENT ROW
        ) AS avg_volume_20,

        COUNT(*) OVER
        (
            PARTITION BY c.security_id
            ORDER BY b.traded_date
            ROWS BETWEEN 19 PRECEDING AND CURRENT ROW
        ) AS volume_window_sessions

    FROM candidates c

    JOIN trn.nse_sec_bhavdata b
      ON b.symbol = c.symbol
     AND b.series = 'EQ'

     -- Enough historical data for the 20-session volume window.
     AND b.traded_date >= c.base_low_date - INTERVAL '60 days'
     AND b.traded_date <= c.trade_date
),

-- ============================================================================
-- Now restrict observations to AFTER the base low.
-- Base-low session remains available indirectly as prev_close for first day.
-- ============================================================================

post_low_data AS
(
    SELECT
        security_id,
        symbol,
        trade_date,
        base_low_date,
        traded_date,
        high_price,
        low_price,
        close_price,
        traded_quantity,
        prev_close,
        avg_volume_20,
        volume_window_sessions,

        (
            (close_price - prev_close)
            / NULLIF(prev_close, 0)
            * 100
        ) AS daily_return_pct,

        (
            (high_price - low_price)
            / NULLIF(close_price, 0)
            * 100
        ) AS range_pct,

        CASE
            WHEN close_price < prev_close THEN 1
            ELSE 0
        END AS is_down_day,

        CASE
            WHEN close_price < prev_close
             AND volume_window_sessions >= 20
             AND traded_quantity > avg_volume_20
            THEN 1
            ELSE 0
        END AS is_high_volume_down_day

    FROM history

    WHERE traded_date > base_low_date
),

resolved AS
(
    SELECT
        security_id,
        trade_date,

        ROUND(
            (
                SUM(is_down_day) * 100.0
                / NULLIF(COUNT(*), 0)
            )::numeric,
            4
        ) AS down_day_ratio_pct,

        ROUND(
            AVG(daily_return_pct)
            FILTER (WHERE is_down_day = 1)::numeric,
            4
        ) AS avg_down_day_return_pct,

        ROUND(
            MIN(daily_return_pct)
            FILTER (WHERE is_down_day = 1)::numeric,
            4
        ) AS worst_down_day_return_pct,

        ROUND(
            AVG(range_pct)
            FILTER (WHERE is_down_day = 1)::numeric,
            4
        ) AS avg_down_day_range_pct,

        ROUND(
            MAX(range_pct)
            FILTER (WHERE is_down_day = 1)::numeric,
            4
        ) AS max_down_day_range_pct,

        ROUND(
            (
                SUM(is_high_volume_down_day) * 100.0
                /
                NULLIF(
                    SUM(is_down_day),
                    0
                )
            )::numeric,
            4
        ) AS high_volume_down_day_ratio_pct

    FROM post_low_data

    GROUP BY
        security_id,
        trade_date
)

UPDATE trn.stock_base_quality_daily t

SET
    down_day_ratio_pct =
        r.down_day_ratio_pct,

    avg_down_day_return_pct =
        r.avg_down_day_return_pct,

    worst_down_day_return_pct =
        r.worst_down_day_return_pct,

    avg_down_day_range_pct =
        r.avg_down_day_range_pct,

    max_down_day_range_pct =
        r.max_down_day_range_pct,

    high_volume_down_day_ratio_pct =
        r.high_volume_down_day_ratio_pct

FROM resolved r

WHERE t.security_id = r.security_id
  AND t.trade_date = r.trade_date;