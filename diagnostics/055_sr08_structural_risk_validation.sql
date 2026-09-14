-- ============================================================================
-- MomentumLab
-- Diagnostic : SR08 Structural Risk Validation
-- File       : 055_sr08_structural_risk_validation.sql
-- Version    : 1.0
--
-- Research window:
--   Observation dates : 2026-08-03 through 2026-09-04
--   Forward horizon   : 5 trading sessions
--   Population        : pivot_proximity_pct BETWEEN -2 AND 0
--
-- PURPOSE
-- -------
-- Determine whether SR08 (pivot_to_stop_risk_atr) should be interpreted as:
--
--   1. a setup-readiness / breakout-prediction feature, or
--   2. a structural-risk / trade-construction feature.
--
-- VALIDATED FINDING
-- -----------------
-- SR08 does not show a monotonic relationship with forward MFE.
--
-- Forward MAE shows some deterioration as structural risk increases through
-- the first three bands, but the relationship is not monotonic because the
-- >3.01 ATR group improves again.
--
-- Therefore:
--
--   SR08 SHOULD NOT currently be converted into a monotonic readiness score.
--
--   SR08 SHOULD be retained as a structural-risk / trade-construction
--   measurement for stop placement, position sizing and R-risk analysis.
--
-- Current evidence does NOT justify a rule such as:
--       "lower pivot_to_stop_risk_atr = better setup"
--
-- Revisit after a substantially larger historical sample is available.
-- ============================================================================
-- ============================================================================
-- SR08 VALIDATION A
-- Structural Risk vs Forward 5-Session MFE
--
-- Observation population:
--   2026-08-03 through 2026-09-04
--   pivot_proximity_pct BETWEEN -2 AND 0
--
-- MFE is measured from OBSERVATION CLOSE, not pivot price.
-- Forward horizon = next 5 TRADING sessions.
-- ============================================================================

WITH observations AS
(
    SELECT
        r.security_id,
        s.symbol,
        r.trade_date,
        r.pivot_proximity_pct,
        r.pivot_to_stop_risk_atr,
        b.close_price AS observation_close,
        tc.trading_day_number
    FROM trn.stock_setup_readiness_daily r
    JOIN ref.ref_nse_equity_security s
      ON s.security_id = r.security_id
    JOIN trn.nse_sec_bhavdata b
      ON b.symbol      = s.symbol
     AND b.traded_date = r.trade_date
     AND b.series      = 'EQ'
    JOIN ref.trading_calendar tc
      ON tc.traded_date = r.trade_date
    WHERE r.trade_date BETWEEN DATE '2026-08-03'
                           AND DATE '2026-09-04'
      AND r.pivot_proximity_pct BETWEEN -2 AND 0
      AND r.pivot_to_stop_risk_atr IS NOT NULL
),
forward_prices AS
(
    SELECT
        o.security_id,
        o.trade_date,
        o.pivot_proximity_pct,
        o.pivot_to_stop_risk_atr,
        o.observation_close,
        MAX(f.high_price) AS forward_5d_high
    FROM observations o
    JOIN ref.trading_calendar ftc
      ON ftc.trading_day_number
         BETWEEN o.trading_day_number + 1
             AND o.trading_day_number + 5
    JOIN trn.nse_sec_bhavdata f
      ON f.symbol      = o.symbol
     AND f.traded_date = ftc.traded_date
     AND f.series      = 'EQ'
    GROUP BY
        o.security_id,
        o.trade_date,
        o.pivot_proximity_pct,
        o.pivot_to_stop_risk_atr,
        o.observation_close
),
outcomes AS
(
    SELECT
        *,
        ((forward_5d_high - observation_close)
          / NULLIF(observation_close, 0)) * 100.0 AS mfe_5d_pct
    FROM forward_prices
),
bucketed AS
(
    SELECT
        *,
        CASE
            WHEN pivot_to_stop_risk_atr <= 1.84
                THEN 'Q1 <= 1.84 ATR'
            WHEN pivot_to_stop_risk_atr <= 2.39
                THEN 'Q2 1.84-2.39 ATR'
            WHEN pivot_to_stop_risk_atr <= 3.01
                THEN 'Q3 2.39-3.01 ATR'
            ELSE 'Q4 > 3.01 ATR'
        END AS risk_band
    FROM outcomes
)
SELECT
    risk_band,
    COUNT(*) AS n,

    ROUND(AVG(pivot_to_stop_risk_atr), 2) AS avg_risk_atr,
    ROUND(AVG(pivot_proximity_pct), 2)    AS avg_proximity_pct,
    ROUND(AVG(mfe_5d_pct), 2)             AS avg_mfe_5d_pct,

    COUNT(*) FILTER
        (WHERE mfe_5d_pct >= 2) AS mfe_ge_2_count,

    ROUND(
        100.0 * COUNT(*) FILTER (WHERE mfe_5d_pct >= 2)
        / COUNT(*), 2
    ) AS mfe_ge_2_pct,

    COUNT(*) FILTER
        (WHERE mfe_5d_pct >= 3) AS mfe_ge_3_count,

    ROUND(
        100.0 * COUNT(*) FILTER (WHERE mfe_5d_pct >= 3)
        / COUNT(*), 2
    ) AS mfe_ge_3_pct,

    COUNT(*) FILTER
        (WHERE mfe_5d_pct >= 5) AS mfe_ge_5_count,

    ROUND(
        100.0 * COUNT(*) FILTER (WHERE mfe_5d_pct >= 5)
        / COUNT(*), 2
    ) AS mfe_ge_5_pct

FROM bucketed
GROUP BY risk_band
ORDER BY
    MIN(pivot_to_stop_risk_atr);

-- ============================================================================
-- SR08 VALIDATION B
-- Structural Risk vs Forward 5-Session MAE
--
-- Observation population:
--   2026-08-03 through 2026-09-04
--   pivot_proximity_pct BETWEEN -2 AND 0
--
-- MAE is measured from OBSERVATION CLOSE.
-- Forward horizon = next 5 TRADING sessions.
-- Negative MAE represents adverse movement.
-- ============================================================================

WITH observations AS
(
    SELECT
        r.security_id,
        s.symbol,
        r.trade_date,
        r.pivot_proximity_pct,
        r.pivot_to_stop_risk_atr,
        b.close_price AS observation_close,
        tc.trading_day_number
    FROM trn.stock_setup_readiness_daily r
    JOIN ref.ref_nse_equity_security s
      ON s.security_id = r.security_id
    JOIN trn.nse_sec_bhavdata b
      ON b.symbol      = s.symbol
     AND b.traded_date = r.trade_date
     AND b.series      = 'EQ'
    JOIN ref.trading_calendar tc
      ON tc.traded_date = r.trade_date
    WHERE r.trade_date BETWEEN DATE '2026-08-03'
                           AND DATE '2026-09-04'
      AND r.pivot_proximity_pct BETWEEN -2 AND 0
      AND r.pivot_to_stop_risk_atr IS NOT NULL
),
forward_prices AS
(
    SELECT
        o.security_id,
        o.trade_date,
        o.pivot_proximity_pct,
        o.pivot_to_stop_risk_atr,
        o.observation_close,
        MIN(f.low_price) AS forward_5d_low
    FROM observations o
    JOIN ref.trading_calendar ftc
      ON ftc.trading_day_number
         BETWEEN o.trading_day_number + 1
             AND o.trading_day_number + 5
    JOIN trn.nse_sec_bhavdata f
      ON f.symbol      = o.symbol
     AND f.traded_date = ftc.traded_date
     AND f.series      = 'EQ'
    GROUP BY
        o.security_id,
        o.trade_date,
        o.pivot_proximity_pct,
        o.pivot_to_stop_risk_atr,
        o.observation_close
),
outcomes AS
(
    SELECT
        *,
        ((forward_5d_low - observation_close)
          / NULLIF(observation_close, 0)) * 100.0 AS mae_5d_pct
    FROM forward_prices
),
bucketed AS
(
    SELECT
        *,
        CASE
            WHEN pivot_to_stop_risk_atr <= 1.84
                THEN 'Q1 <= 1.84 ATR'
            WHEN pivot_to_stop_risk_atr <= 2.39
                THEN 'Q2 1.84-2.39 ATR'
            WHEN pivot_to_stop_risk_atr <= 3.01
                THEN 'Q3 2.39-3.01 ATR'
            ELSE 'Q4 > 3.01 ATR'
        END AS risk_band
    FROM outcomes
)
SELECT
    risk_band,
    COUNT(*) AS n,

    ROUND(AVG(pivot_to_stop_risk_atr), 2) AS avg_risk_atr,
    ROUND(AVG(pivot_proximity_pct), 2)    AS avg_proximity_pct,
    ROUND(AVG(mae_5d_pct), 2)             AS avg_mae_5d_pct,

    ROUND(
        PERCENTILE_CONT(0.5)
        WITHIN GROUP (ORDER BY mae_5d_pct)::numeric,
        2
    ) AS median_mae_5d_pct,

    COUNT(*) FILTER
        (WHERE mae_5d_pct <= -2) AS mae_le_minus_2_count,

    ROUND(
        100.0 * COUNT(*) FILTER (WHERE mae_5d_pct <= -2)
        / COUNT(*), 2
    ) AS mae_le_minus_2_pct,

    COUNT(*) FILTER
        (WHERE mae_5d_pct <= -3) AS mae_le_minus_3_count,

    ROUND(
        100.0 * COUNT(*) FILTER (WHERE mae_5d_pct <= -3)
        / COUNT(*), 2
    ) AS mae_le_minus_3_pct,

    COUNT(*) FILTER
        (WHERE mae_5d_pct <= -5) AS mae_le_minus_5_count,

    ROUND(
        100.0 * COUNT(*) FILTER (WHERE mae_5d_pct <= -5)
        / COUNT(*), 2
    ) AS mae_le_minus_5_pct

FROM bucketed
GROUP BY risk_band
ORDER BY
    MIN(pivot_to_stop_risk_atr);