-- ============================================================================
-- MomentumLab
-- Feature     : SR03 - Breakout Volume State
-- File        : 049_sr03_breakout_volume_state.sql
-- Version     : 1.1
-- Description : Classifies Relative Volume (20D) into descriptive
--               breakout-volume states.
--
-- Historicalization change:
--   - evaluation_date supplied externally.
--   - Classification logic unchanged from Version 1.0.
--
-- Important:
--   relative_volume_20 is the raw measurement.
--   breakout_volume_state is an interpretation layer.
-- ============================================================================

WITH params AS
(
    SELECT CAST(:evaluation_date AS DATE) AS evaluation_date
)

UPDATE trn.stock_setup_readiness_daily r

SET
    breakout_volume_state =
        CASE
            WHEN r.relative_volume_20 IS NULL
                THEN 'NO_VOLUME_DATA'

            WHEN r.relative_volume_20 < 0.75
                THEN 'LOW_VOLUME'

            WHEN r.relative_volume_20 < 1.00
                THEN 'NORMAL_VOLUME'

            WHEN r.relative_volume_20 < 1.50
                THEN 'ELEVATED_VOLUME'

            ELSE 'HIGH_VOLUME'
        END,

    created_date = CURRENT_TIMESTAMP

FROM params p

WHERE r.trade_date = p.evaluation_date;