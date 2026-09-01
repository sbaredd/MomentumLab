-- ============================================================================
-- MomentumLab
-- File        : 054_sr08_structural_entry_risk.sql
-- Version     : 1.1
-- Description : SR08 - Structural Entry Risk
--
-- Historicalization change:
--   - evaluation_date supplied externally.
--   - SR08 measurement logic unchanged from Version 1.0.
--
-- Purpose:
--   Measures structural risk from the actionable pivot to the lowest price
--   of the 5 completed trading sessions immediately BEFORE evaluation date.
--
-- Measurements:
--   1. prebreakout_5d_low
--   2. pivot_to_stop_risk_pct
--   3. pivot_to_stop_risk_atr
--
-- Important:
--   - Evaluation / breakout session is EXCLUDED.
--   - Uses existing actionable pivot from Setup Readiness.
--   - Uses existing ATR% calculated by SR04.
--   - No scoring or arbitrary risk thresholds are applied here.
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
        b.low_price,

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
        low_price

    FROM ranked_sessions

    WHERE rn <= 5
),

prebreakout_low AS
(
    SELECT
        security_id,
        COUNT(*) AS session_count,
        MIN(low_price) AS prebreakout_5d_low

    FROM recent_5

    GROUP BY security_id
),

calculated AS
(
    SELECT
        r.security_id,

        CASE
            WHEN pbl.session_count = 5
            THEN pbl.prebreakout_5d_low
        END AS prebreakout_5d_low,

        CASE
            WHEN pbl.session_count = 5
             AND r.pivot_price IS NOT NULL
             AND r.pivot_price <> 0
             AND pbl.prebreakout_5d_low IS NOT NULL
            THEN
                (
                    (r.pivot_price - pbl.prebreakout_5d_low)
                    / r.pivot_price
                ) * 100
        END AS pivot_to_stop_risk_pct,

        CASE
            WHEN pbl.session_count = 5
             AND r.pivot_price IS NOT NULL
             AND r.pivot_price <> 0
             AND pbl.prebreakout_5d_low IS NOT NULL
             AND r.atr_pct IS NOT NULL
             AND r.atr_pct <> 0
            THEN
                (
                    (
                        (r.pivot_price - pbl.prebreakout_5d_low)
                        / r.pivot_price
                    ) * 100
                ) / r.atr_pct
        END AS pivot_to_stop_risk_atr

    FROM trn.stock_setup_readiness_daily r

    JOIN prebreakout_low pbl
      ON pbl.security_id = r.security_id

    CROSS JOIN params p

    WHERE r.trade_date = p.evaluation_date
)

UPDATE trn.stock_setup_readiness_daily r

SET
    prebreakout_5d_low =
        c.prebreakout_5d_low,

    pivot_to_stop_risk_pct =
        c.pivot_to_stop_risk_pct,

    pivot_to_stop_risk_atr =
        c.pivot_to_stop_risk_atr

FROM calculated c
CROSS JOIN params p

WHERE r.security_id = c.security_id
  AND r.trade_date = p.evaluation_date;