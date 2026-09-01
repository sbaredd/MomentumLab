-- ============================================================================
-- MomentumLab
-- Feature     : SR05 - Pivot Tightness
-- File        : 051_sr05_pivot_tightness.sql
-- Version     : 1.1
-- Description : Measures short-term price compression around the structural
--               pivot using the most recent 5 trading sessions.
--
-- Historicalization change:
--   - evaluation_date supplied externally.
--   - SR05 measurement logic unchanged from Version 1.0.
--
-- Raw measurements only.
-- No tightness thresholds or readiness states are imposed here.
-- ============================================================================

WITH params AS
(
    SELECT CAST(:evaluation_date AS DATE) AS evaluation_date
),

universe AS
(
    SELECT
        s.security_id,
        s.symbol
    FROM ref.security_universe_membership um
    JOIN ref.ref_nse_equity_security s
        ON s.security_id = um.security_id
    WHERE um.universe_code = 'NIFTY_100'
),

recent_prices AS
(
    SELECT
        u.security_id,
        b.traded_date,
        b.high_price,
        b.low_price,
        b.close_price,

        ROW_NUMBER() OVER
        (
            PARTITION BY u.security_id
            ORDER BY b.traded_date DESC
        ) AS rn

    FROM universe u

    JOIN trn.nse_sec_bhavdata b
        ON b.symbol = u.symbol

    CROSS JOIN params p

    WHERE b.traded_date < p.evaluation_date
      AND b.series = 'EQ'
),

five_session_stats AS
(
    SELECT
        security_id,

        COUNT(*) AS session_count,

        MAX(high_price) AS highest_high_5,
        MIN(low_price) AS lowest_low_5,

        MAX(close_price) AS highest_close_5,
        MIN(close_price) AS lowest_close_5

    FROM recent_prices

    WHERE rn <= 5

    GROUP BY security_id
),

measurements AS
(
    SELECT
        security_id,

        CASE
            WHEN session_count < 5
              OR lowest_low_5 IS NULL
              OR lowest_low_5 = 0
            THEN NULL

            ELSE ROUND(
                (
                    (highest_high_5 - lowest_low_5)
                    / lowest_low_5
                    * 100
                )::numeric,
                4
            )
        END AS recent_5_range_pct,

        CASE
            WHEN session_count < 5
              OR lowest_close_5 IS NULL
              OR lowest_close_5 = 0
            THEN NULL

            ELSE ROUND(
                (
                    (highest_close_5 - lowest_close_5)
                    / lowest_close_5
                    * 100
                )::numeric,
                4
            )
        END AS recent_5_close_tightness_pct

    FROM five_session_stats
)

UPDATE trn.stock_setup_readiness_daily r

SET
    recent_5_range_pct =
        m.recent_5_range_pct,

    recent_5_close_tightness_pct =
        m.recent_5_close_tightness_pct,

    created_date = CURRENT_TIMESTAMP

FROM measurements m
CROSS JOIN params p

WHERE r.security_id = m.security_id
  AND r.trade_date = p.evaluation_date;