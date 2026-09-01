-- ============================================================================
-- MomentumLab
-- File        : 053_sr07_prebreakout_price_progression.sql
-- Version     : 1.1
-- Description : SR07 - Pre-Breakout Price Progression
--
-- Historicalization change:
--   - evaluation_date supplied externally.
--   - SR07 measurement logic unchanged from Version 1.0.
--
-- Purpose:
--   Measures whether price is progressing upward / pressing toward the pivot
--   during the 5 completed trading sessions immediately BEFORE the
--   evaluation date.
--
-- Important:
--   Evaluation / breakout session is EXCLUDED.
--
-- Measurements:
--   1. prebreakout_5d_return_pct
--   2. prebreakout_close_position_pct
--
-- No scoring or readiness thresholds are applied here.
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

ranked_sessions AS
(
    SELECT
        u.security_id,
        u.symbol,
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

    WHERE b.series = 'EQ'
      AND b.traded_date < p.evaluation_date
),

recent_5 AS
(
    SELECT
        security_id,
        symbol,
        traded_date,
        high_price,
        low_price,
        close_price,
        rn
    FROM ranked_sessions
    WHERE rn <= 5
),

measurements AS
(
    SELECT
        security_id,

        COUNT(*) AS session_count,

        MAX(high_price) AS period_high,
        MIN(low_price)  AS period_low,

        MAX(close_price) FILTER (WHERE rn = 5)
            AS first_close,

        MAX(close_price) FILTER (WHERE rn = 1)
            AS last_close

    FROM recent_5

    GROUP BY security_id
),

calculated AS
(
    SELECT
        security_id,

        CASE
            WHEN session_count = 5
             AND first_close IS NOT NULL
             AND first_close <> 0
            THEN
                (
                    (last_close - first_close)
                    / first_close
                ) * 100
        END AS prebreakout_5d_return_pct,

        CASE
            WHEN session_count = 5
             AND period_high IS NOT NULL
             AND period_low IS NOT NULL
             AND period_high <> period_low
            THEN
                (
                    (last_close - period_low)
                    / (period_high - period_low)
                ) * 100
        END AS prebreakout_close_position_pct

    FROM measurements
)

UPDATE trn.stock_setup_readiness_daily r

SET
    prebreakout_5d_return_pct =
        c.prebreakout_5d_return_pct,

    prebreakout_close_position_pct =
        c.prebreakout_close_position_pct

FROM calculated c
CROSS JOIN params p

WHERE r.security_id = c.security_id
  AND r.trade_date = p.evaluation_date;