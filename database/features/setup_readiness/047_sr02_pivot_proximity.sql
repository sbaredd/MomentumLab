-- ============================================================================
-- MomentumLab
-- Feature     : SR02 - Pivot Proximity
-- File        : 047_sr02_pivot_proximity.sql
-- Version     : 1.1
-- Description : Measures how far price is from the active structural pivot.
--
-- Historicalization change:
--   - evaluation_date is now supplied externally.
--   - SR02 calculation logic is unchanged from Version 1.0.
--
-- Interpretation:
--
--   Negative value -> price is below pivot
--   Zero           -> price is at pivot
--   Positive value -> price is above pivot
--
-- Formula:
--
--   ((close_price - pivot_price) / pivot_price) * 100
--
-- Notes:
--   - NO_ACTIVE_PIVOT remains NULL.
--   - Raw measurement only.
--   - No readiness threshold or score is applied here.
-- ============================================================================

WITH params AS
(
    SELECT CAST(:evaluation_date AS DATE) AS evaluation_date
)

UPDATE trn.stock_setup_readiness_daily r
SET
    pivot_proximity_pct =
        CASE
            WHEN r.pivot_price IS NULL
                 OR r.pivot_price = 0
            THEN NULL

            ELSE ROUND(
                (
                    r.close_vs_pivot_pct
                )::numeric,
                4
            )
        END,

    created_date = CURRENT_TIMESTAMP

FROM params p

WHERE r.trade_date = p.evaluation_date;