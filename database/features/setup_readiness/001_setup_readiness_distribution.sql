-- ============================================================================
-- MomentumLab
-- Diagnostic  : Setup Readiness Distribution Analysis
-- File        : 001_setup_readiness_distribution.sql
-- Version     : 1.0
-- Purpose     : Examine the empirical distribution of raw Setup Readiness
--               measurements for securities with actionable pivots.
--
-- IMPORTANT:
--   - Diagnostic only.
--   - No scoring.
--   - No classification.
--   - No readiness thresholds.
--   - SR measurements are not recalculated here.
-- ============================================================================


-- ============================================================================
-- PARAMETERS
-- ============================================================================

WITH params AS
(
    SELECT DATE '2026-08-13' AS evaluation_date
),


-- ============================================================================
-- ACTIONABLE PIVOT POPULATION
-- ============================================================================

population AS
(
    SELECT
        r.security_id,
        s.symbol,
        r.trade_date,

        r.pivot_date,
        r.pivot_price,
        r.pivot_type,

        -- SR02
        r.pivot_proximity_pct,

        -- SR05
        r.recent_5_range_pct,
        r.recent_5_close_tightness_pct,

        -- SR06
        r.recent_5_volume_vs_20d_pct,

        -- SR07
        r.prebreakout_5d_return_pct,
        r.prebreakout_close_position_pct,

        -- SR08
        r.pivot_to_stop_risk_pct,
        r.pivot_to_stop_risk_atr

    FROM trn.stock_setup_readiness_daily r

    JOIN ref.ref_nse_equity_security s
        ON s.security_id = r.security_id

    CROSS JOIN params p

    WHERE r.trade_date = p.evaluation_date

      -- Actionable structural pivot exists
      AND r.pivot_price IS NOT NULL
),


-- ============================================================================
-- DISTRIBUTION STATISTICS
-- ============================================================================

distribution AS
(
    SELECT

        COUNT(*) AS population_size,

        -- --------------------------------------------------------------------
        -- SR02 - Pivot Proximity
        -- --------------------------------------------------------------------

        percentile_cont(0.10)
            WITHIN GROUP (ORDER BY pivot_proximity_pct)
            AS sr02_p10,

        percentile_cont(0.25)
            WITHIN GROUP (ORDER BY pivot_proximity_pct)
            AS sr02_p25,

        percentile_cont(0.50)
            WITHIN GROUP (ORDER BY pivot_proximity_pct)
            AS sr02_p50,

        percentile_cont(0.75)
            WITHIN GROUP (ORDER BY pivot_proximity_pct)
            AS sr02_p75,

        percentile_cont(0.90)
            WITHIN GROUP (ORDER BY pivot_proximity_pct)
            AS sr02_p90,


        -- --------------------------------------------------------------------
        -- SR05 - 5-Day Range
        -- --------------------------------------------------------------------

        percentile_cont(0.10)
            WITHIN GROUP (ORDER BY recent_5_range_pct)
            AS sr05_range_p10,

        percentile_cont(0.25)
            WITHIN GROUP (ORDER BY recent_5_range_pct)
            AS sr05_range_p25,

        percentile_cont(0.50)
            WITHIN GROUP (ORDER BY recent_5_range_pct)
            AS sr05_range_p50,

        percentile_cont(0.75)
            WITHIN GROUP (ORDER BY recent_5_range_pct)
            AS sr05_range_p75,

        percentile_cont(0.90)
            WITHIN GROUP (ORDER BY recent_5_range_pct)
            AS sr05_range_p90,


        -- --------------------------------------------------------------------
        -- SR05 - Close Tightness
        -- --------------------------------------------------------------------

        percentile_cont(0.10)
            WITHIN GROUP (ORDER BY recent_5_close_tightness_pct)
            AS sr05_close_p10,

        percentile_cont(0.25)
            WITHIN GROUP (ORDER BY recent_5_close_tightness_pct)
            AS sr05_close_p25,

        percentile_cont(0.50)
            WITHIN GROUP (ORDER BY recent_5_close_tightness_pct)
            AS sr05_close_p50,

        percentile_cont(0.75)
            WITHIN GROUP (ORDER BY recent_5_close_tightness_pct)
            AS sr05_close_p75,

        percentile_cont(0.90)
            WITHIN GROUP (ORDER BY recent_5_close_tightness_pct)
            AS sr05_close_p90,


        -- --------------------------------------------------------------------
        -- SR06 - 5-Day Volume vs 20-Day Volume
        -- --------------------------------------------------------------------

        percentile_cont(0.10)
            WITHIN GROUP (ORDER BY recent_5_volume_vs_20d_pct)
            AS sr06_p10,

        percentile_cont(0.25)
            WITHIN GROUP (ORDER BY recent_5_volume_vs_20d_pct)
            AS sr06_p25,

        percentile_cont(0.50)
            WITHIN GROUP (ORDER BY recent_5_volume_vs_20d_pct)
            AS sr06_p50,

        percentile_cont(0.75)
            WITHIN GROUP (ORDER BY recent_5_volume_vs_20d_pct)
            AS sr06_p75,

        percentile_cont(0.90)
            WITHIN GROUP (ORDER BY recent_5_volume_vs_20d_pct)
            AS sr06_p90,


        -- --------------------------------------------------------------------
        -- SR07 - 5-Day Price Progression
        -- --------------------------------------------------------------------

        percentile_cont(0.10)
            WITHIN GROUP (ORDER BY prebreakout_5d_return_pct)
            AS sr07_return_p10,

        percentile_cont(0.25)
            WITHIN GROUP (ORDER BY prebreakout_5d_return_pct)
            AS sr07_return_p25,

        percentile_cont(0.50)
            WITHIN GROUP (ORDER BY prebreakout_5d_return_pct)
            AS sr07_return_p50,

        percentile_cont(0.75)
            WITHIN GROUP (ORDER BY prebreakout_5d_return_pct)
            AS sr07_return_p75,

        percentile_cont(0.90)
            WITHIN GROUP (ORDER BY prebreakout_5d_return_pct)
            AS sr07_return_p90,


        -- --------------------------------------------------------------------
        -- SR07 - Close Position
        -- --------------------------------------------------------------------

        percentile_cont(0.10)
            WITHIN GROUP (ORDER BY prebreakout_close_position_pct)
            AS sr07_close_position_p10,

        percentile_cont(0.25)
            WITHIN GROUP (ORDER BY prebreakout_close_position_pct)
            AS sr07_close_position_p25,

        percentile_cont(0.50)
            WITHIN GROUP (ORDER BY prebreakout_close_position_pct)
            AS sr07_close_position_p50,

        percentile_cont(0.75)
            WITHIN GROUP (ORDER BY prebreakout_close_position_pct)
            AS sr07_close_position_p75,

        percentile_cont(0.90)
            WITHIN GROUP (ORDER BY prebreakout_close_position_pct)
            AS sr07_close_position_p90,


        -- --------------------------------------------------------------------
        -- SR08 - Structural Risk %
        -- --------------------------------------------------------------------

        percentile_cont(0.10)
            WITHIN GROUP (ORDER BY pivot_to_stop_risk_pct)
            AS sr08_risk_pct_p10,

        percentile_cont(0.25)
            WITHIN GROUP (ORDER BY pivot_to_stop_risk_pct)
            AS sr08_risk_pct_p25,

        percentile_cont(0.50)
            WITHIN GROUP (ORDER BY pivot_to_stop_risk_pct)
            AS sr08_risk_pct_p50,

        percentile_cont(0.75)
            WITHIN GROUP (ORDER BY pivot_to_stop_risk_pct)
            AS sr08_risk_pct_p75,

        percentile_cont(0.90)
            WITHIN GROUP (ORDER BY pivot_to_stop_risk_pct)
            AS sr08_risk_pct_p90,


        -- --------------------------------------------------------------------
        -- SR08 - Structural Risk in ATR
        -- --------------------------------------------------------------------

        percentile_cont(0.10)
            WITHIN GROUP (ORDER BY pivot_to_stop_risk_atr)
            AS sr08_risk_atr_p10,

        percentile_cont(0.25)
            WITHIN GROUP (ORDER BY pivot_to_stop_risk_atr)
            AS sr08_risk_atr_p25,

        percentile_cont(0.50)
            WITHIN GROUP (ORDER BY pivot_to_stop_risk_atr)
            AS sr08_risk_atr_p50,

        percentile_cont(0.75)
            WITHIN GROUP (ORDER BY pivot_to_stop_risk_atr)
            AS sr08_risk_atr_p75,

        percentile_cont(0.90)
            WITHIN GROUP (ORDER BY pivot_to_stop_risk_atr)
            AS sr08_risk_atr_p90

    FROM population
)


-- ============================================================================
-- RESULT
-- ============================================================================

SELECT *
FROM distribution;