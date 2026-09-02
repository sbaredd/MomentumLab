-- ============================================================================
-- MomentumLab
-- BQ07 - Energy Stored Diagnostic V2
--
-- Purpose:
--   Test whether the post-low portion of a base is becoming progressively
--   quieter/tighter.
--
-- Measures:
--   1. Range contraction
--   2. Volume dry-up
--   3. Price tightness
--
-- Diagnostic only - NO UPDATE
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
            ORDER BY b.traded_date DESC
        ) AS recent_session_no,

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
            WHEN recent_session_no <= 5
                THEN 'RECENT_5'
            ELSE 'EARLIER'
        END AS phase

    FROM post_low_data
),

summary AS
(
    SELECT
        symbol,

        COUNT(*) AS post_low_sessions,

        -- ------------------------------------------------------------
        -- RANGE
        -- ------------------------------------------------------------

        AVG(range_pct)
            FILTER (WHERE phase = 'EARLIER')
            AS earlier_avg_range_pct,

        AVG(range_pct)
            FILTER (WHERE phase = 'RECENT_5')
            AS recent_5_avg_range_pct,

        -- ------------------------------------------------------------
        -- VOLUME
        -- ------------------------------------------------------------

        AVG(traded_quantity)
            FILTER (WHERE phase = 'EARLIER')
            AS earlier_avg_volume,

        AVG(traded_quantity)
            FILTER (WHERE phase = 'RECENT_5')
            AS recent_5_avg_volume,

        -- ------------------------------------------------------------
        -- RECENT PRICE TIGHTNESS
        --
        -- Measures the high-low envelope of the latest 5 sessions
        -- relative to their average close.
        -- ------------------------------------------------------------

        (
            (
                MAX(high_price)
                    FILTER (WHERE phase = 'RECENT_5')
                -
                MIN(low_price)
                    FILTER (WHERE phase = 'RECENT_5')
            )
            /
            NULLIF(
                AVG(close_price)
                    FILTER (WHERE phase = 'RECENT_5'),
                0
            )
            * 100
        ) AS recent_5_price_tightness_pct

    FROM classified

    GROUP BY symbol
),

resolved AS
(
    SELECT
        *,

        -- ------------------------------------------------------------
        -- RANGE CONTRACTION
        --
        -- Positive = recent range smaller than earlier range
        -- ------------------------------------------------------------

        (
            (
                earlier_avg_range_pct
                -
                recent_5_avg_range_pct
            )
            /
            NULLIF(earlier_avg_range_pct, 0)
            * 100
        ) AS range_contraction_pct,

        -- ------------------------------------------------------------
        -- VOLUME DRY-UP
        --
        -- Positive = recent volume lower than earlier volume
        -- ------------------------------------------------------------

        (
            (
                earlier_avg_volume
                -
                recent_5_avg_volume
            )
            /
            NULLIF(earlier_avg_volume, 0)
            * 100
        ) AS volume_dryup_pct

    FROM summary
)

SELECT
    symbol,
    post_low_sessions,

    ROUND(earlier_avg_range_pct::numeric, 4)
        AS earlier_avg_range_pct,

    ROUND(recent_5_avg_range_pct::numeric, 4)
        AS recent_5_avg_range_pct,

    ROUND(range_contraction_pct::numeric, 4)
        AS range_contraction_pct,

    ROUND(earlier_avg_volume::numeric, 2)
        AS earlier_avg_volume,

    ROUND(recent_5_avg_volume::numeric, 2)
        AS recent_5_avg_volume,

    ROUND(volume_dryup_pct::numeric, 4)
        AS volume_dryup_pct,

    ROUND(recent_5_price_tightness_pct::numeric, 4)
        AS recent_5_price_tightness_pct

FROM resolved

ORDER BY symbol;