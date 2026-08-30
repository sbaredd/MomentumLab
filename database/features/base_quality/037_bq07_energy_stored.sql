-- ============================================================================
-- MomentumLab
-- Feature     : BQ07 - Energy Stored
-- File        : 037_bq07_energy_stored.sql
-- Version     : 2.0
--
-- Purpose:
--   Measure whether the post-low portion of the base has entered a
--   compressed, quieter state capable of supporting expansion.
--
-- Raw features:
--   - range_contraction_pct          (already populated by BQ02)
--   - volume_dryup_pct
--   - recent_5_price_tightness_pct
--
-- Production scope:
--   NIFTY_100
--   Selected evaluation date
--
-- No scoring thresholds in raw feature calculation.
-- ============================================================================

WITH params AS
(
    SELECT
        DATE '2026-08-13' AS evaluation_date,
        'NIFTY_100'::varchar AS universe_code
),

candidates AS
(
    SELECT
        q.security_id,
        s.symbol,
        q.trade_date,
        q.base_low_date

    FROM trn.stock_base_quality_daily q

    JOIN ref.ref_nse_equity_security s
      ON s.security_id = q.security_id

    JOIN ref.security_universe_membership um
      ON um.security_id = q.security_id

    CROSS JOIN params p

    WHERE q.trade_date = p.evaluation_date
      AND um.universe_code = p.universe_code
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
        security_id,
        trade_date,

        AVG(traded_quantity)
            FILTER (WHERE phase = 'EARLIER')
            AS earlier_avg_volume,

        AVG(traded_quantity)
            FILTER (WHERE phase = 'RECENT_5')
            AS recent_5_avg_volume,

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

    GROUP BY
        security_id,
        trade_date
),

resolved AS
(
    SELECT
        security_id,
        trade_date,

        ROUND(
            (
                (
                    earlier_avg_volume
                    -
                    recent_5_avg_volume
                )
                /
                NULLIF(earlier_avg_volume, 0)
                * 100
            )::numeric,
            4
        ) AS volume_dryup_pct,

        ROUND(
            recent_5_price_tightness_pct::numeric,
            4
        ) AS recent_5_price_tightness_pct

    FROM summary
)

UPDATE trn.stock_base_quality_daily t

SET
    volume_dryup_pct =
        r.volume_dryup_pct,

    recent_5_price_tightness_pct =
        r.recent_5_price_tightness_pct

FROM resolved r

CROSS JOIN params p

WHERE t.security_id = r.security_id
  AND t.trade_date  = r.trade_date
  AND t.trade_date  = p.evaluation_date;