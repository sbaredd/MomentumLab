-- ============================================================================
-- MomentumLab
-- Feature : BQ05 - Selling Pressure
-- File    : 035_bq05_selling_pressure.sql
-- Version : 2.0
--
-- Purpose:
--   Measure selling pressure during the post-base-low portion
--   of the current base episode.
--
-- Measures:
--   1. Down-day frequency
--   2. Average down-day severity
--   3. Worst down-day severity
--   4. Average down-day range
--   5. Maximum down-day range
--   6. High-volume down-day frequency
--
-- High-volume definition:
--   Down day where total_traded_volume > 20-session average volume
--
-- Scope:
--   NIFTY_100
--   Selected evaluation date
-- ============================================================================


WITH params AS
(
    SELECT DATE '2026-08-13' AS evaluation_date
),

-- ============================================================================
-- 1. Current Base Episodes
-- ============================================================================

episodes AS
(
    SELECT
        e.security_id,
        s.symbol,
        e.trade_date,
        e.base_low_date,
        e.base_low

    FROM trn.stock_base_episode_daily e

    JOIN ref.ref_nse_equity_security s
      ON s.security_id = e.security_id

    JOIN ref.security_universe_membership um
      ON um.security_id = e.security_id
     AND um.universe_code = 'NIFTY_100'

    CROSS JOIN params p

    WHERE e.trade_date = p.evaluation_date
),

-- ============================================================================
-- 2. Price History
--
-- Include the base-low session only as the LAG anchor.
-- Measurements begin strictly AFTER the base-low date.
-- ============================================================================

price_history AS
(
    SELECT
        e.security_id,
        e.symbol,
        e.trade_date,
        e.base_low_date,

        b.traded_date AS price_date,

        b.high_price,
        b.low_price,
        b.close_price,
        b.traded_quantity,

        f.avg_volume_20,

        LAG(b.close_price) OVER
        (
            PARTITION BY e.security_id
            ORDER BY b.traded_date
        ) AS prev_close

    FROM episodes e

    JOIN trn.nse_sec_bhavdata b
      ON b.symbol = e.symbol
     AND b.traded_date >= e.base_low_date
     AND b.traded_date <= e.trade_date

    LEFT JOIN trn.stock_daily_features f
      ON f.symbol     = e.symbol
     AND f.trade_date = b.traded_date
),

-- ============================================================================
-- 3. Post-Low Sessions
-- ============================================================================

post_low AS
(
    SELECT
        security_id,
        symbol,
        trade_date,
        price_date,

        high_price,
        low_price,
        close_price,
        traded_quantity,
        avg_volume_20,
        prev_close,

        CASE
            WHEN close_price < prev_close
            THEN 1
            ELSE 0
        END AS is_down_day,

        CASE
            WHEN prev_close IS NOT NULL
             AND prev_close <> 0
            THEN
                (
                    (close_price - prev_close)
                    / prev_close
                ) * 100.0
        END AS daily_return_pct,

        CASE
            WHEN close_price IS NOT NULL
             AND close_price <> 0
            THEN
                (
                    (high_price - low_price)
                    / close_price
                ) * 100.0
        END AS range_pct,

        CASE
            WHEN close_price < prev_close
             AND avg_volume_20 IS NOT NULL
             AND traded_quantity > avg_volume_20
            THEN 1
            ELSE 0
        END AS is_high_volume_down_day

    FROM price_history

    WHERE price_date > base_low_date
),

-- ============================================================================
-- 4. Selling Pressure Measurements
-- ============================================================================

measurements AS
(
    SELECT
        security_id,
        trade_date,

        COUNT(*) AS post_low_sessions,

        COUNT(*) FILTER
        (
            WHERE is_down_day = 1
        ) AS down_days,

        (
            COUNT(*) FILTER
            (
                WHERE is_down_day = 1
            )
            * 100.0
            /
            NULLIF(COUNT(*), 0)
        ) AS down_day_ratio_pct,

        AVG(daily_return_pct) FILTER
        (
            WHERE is_down_day = 1
        ) AS avg_down_day_return_pct,

        MIN(daily_return_pct) FILTER
        (
            WHERE is_down_day = 1
        ) AS worst_down_day_return_pct,

        AVG(range_pct) FILTER
        (
            WHERE is_down_day = 1
        ) AS avg_down_day_range_pct,

        MAX(range_pct) FILTER
        (
            WHERE is_down_day = 1
        ) AS max_down_day_range_pct,

        (
            COUNT(*) FILTER
            (
                WHERE is_down_day = 1
                  AND is_high_volume_down_day = 1
            )
            * 100.0
            /
            NULLIF
            (
                COUNT(*) FILTER
                (
                    WHERE is_down_day = 1
                ),
                0
            )
        ) AS high_volume_down_day_ratio_pct

    FROM post_low

    GROUP BY
        security_id,
        trade_date

    HAVING COUNT(*) >= 6
)

-- ============================================================================
-- 5. Update Base Quality
-- ============================================================================

UPDATE trn.stock_base_quality_daily q

SET
    down_day_ratio_pct =
        m.down_day_ratio_pct,

    avg_down_day_return_pct =
        m.avg_down_day_return_pct,

    worst_down_day_return_pct =
        m.worst_down_day_return_pct,

    avg_down_day_range_pct =
        m.avg_down_day_range_pct,

    max_down_day_range_pct =
        m.max_down_day_range_pct,

    high_volume_down_day_ratio_pct =
        m.high_volume_down_day_ratio_pct

FROM measurements m

CROSS JOIN params p

WHERE q.security_id = m.security_id
  AND q.trade_date  = m.trade_date
  AND q.trade_date  = p.evaluation_date;