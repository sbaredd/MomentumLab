-- ============================================================================
-- MomentumLab
-- Diagnostic  : Setup Readiness Historical Population
-- File        : 001_setup_readiness_population.sql
-- Version     : 1.0
-- Purpose     : Describe the historical Setup Readiness calibration
--               population for securities with actionable structural pivots.
--
-- IMPORTANT:
--   - Diagnostic only.
--   - No scoring.
--   - No classification.
--   - No thresholds.
--   - Existing SR measurements are not recalculated.
-- ============================================================================


-- ============================================================================
-- 1. HISTORICAL COVERAGE
-- ============================================================================

SELECT
    MIN(trade_date) AS first_trade_date,
    MAX(trade_date) AS last_trade_date,
    COUNT(DISTINCT trade_date) AS trading_dates,
    COUNT(*) AS total_observations,
    COUNT(*) FILTER
    (
        WHERE pivot_price IS NOT NULL
    ) AS actionable_pivot_observations,
    COUNT(*) FILTER
    (
        WHERE pivot_price IS NULL
    ) AS no_active_pivot_observations
FROM trn.stock_setup_readiness_daily;


-- ============================================================================
-- 2. POPULATION BY DATE
-- ============================================================================

SELECT
    trade_date,
    COUNT(*) AS total_stocks,
    COUNT(*) FILTER
    (
        WHERE pivot_price IS NOT NULL
    ) AS actionable_pivots,
    COUNT(*) FILTER
    (
        WHERE pivot_price IS NULL
    ) AS no_active_pivots,

    ROUND(
        (
            COUNT(*) FILTER
            (
                WHERE pivot_price IS NOT NULL
            )::numeric
            / NULLIF(COUNT(*), 0)
            * 100
        ),
        2
    ) AS actionable_pivot_pct

FROM trn.stock_setup_readiness_daily

GROUP BY trade_date
ORDER BY trade_date;


-- ============================================================================
-- 3. ACTIONABLE PIVOT TYPE DISTRIBUTION
-- ============================================================================

SELECT
    pivot_type,
    COUNT(*) AS observations,

    ROUND(
        (
            COUNT(*)::numeric
            / NULLIF(
                SUM(COUNT(*)) OVER (),
                0
            )
            * 100
        ),
        2
    ) AS population_pct

FROM trn.stock_setup_readiness_daily

WHERE pivot_price IS NOT NULL

GROUP BY pivot_type
ORDER BY observations DESC;


-- ============================================================================
-- 4. FEATURE COMPLETENESS - ACTIONABLE PIVOT POPULATION
-- ============================================================================

SELECT
    COUNT(*) AS actionable_pivot_observations,

    COUNT(pivot_proximity_pct)
        AS sr02_pivot_proximity,

    COUNT(recent_5_range_pct)
        AS sr05_range,

    COUNT(recent_5_close_tightness_pct)
        AS sr05_close_tightness,

    COUNT(recent_5_volume_vs_20d_pct)
        AS sr06_volume_dryup,

    COUNT(prebreakout_5d_return_pct)
        AS sr07_return,

    COUNT(prebreakout_close_position_pct)
        AS sr07_close_position,

    COUNT(pivot_to_stop_risk_pct)
        AS sr08_risk_pct,

    COUNT(pivot_to_stop_risk_atr)
        AS sr08_risk_atr

FROM trn.stock_setup_readiness_daily

WHERE pivot_price IS NOT NULL;