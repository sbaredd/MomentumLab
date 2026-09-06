-- ============================================================================
-- MomentumLab
-- Feature     : SR02A - Pivot Proximity Direction
-- File        : 047a_sr02a_pivot_proximity_direction.sql
-- Version     : 1.0
-- Description : Measures one-session change in pivot proximity and classifies
--               whether price is approaching or retreating from the same
--               structural pivot.
--
-- Parameter:
--   evaluation_date
--
-- Interpretation:
--
--   change > 0  -> APPROACHING_PIVOT
--   change < 0  -> RETREATING_FROM_PIVOT
--   change = 0  -> UNCHANGED
--   NULL        -> no prior comparable observation
--
-- Important:
--   Comparison is valid only when the previous observation belongs to the
--   same structural pivot:
--
--     security_id + pivot_date + pivot_price
--
--   A pivot change must NOT be interpreted as proximity direction.
--
-- Notes:
--   - Raw state/trajectory feature only.
--   - No readiness threshold or score is applied here.
--   - NO_ACTIVE_PIVOT remains NULL.
-- ============================================================================

WITH params AS
(
    SELECT CAST(:evaluation_date AS DATE) AS evaluation_date
),

current_rows AS
(
    SELECT
        r.security_id,
        r.trade_date,
        r.pivot_date,
        r.pivot_price,
        r.pivot_proximity_pct

    FROM trn.stock_setup_readiness_daily r
    CROSS JOIN params p

    WHERE r.trade_date = p.evaluation_date
),

previous_comparable AS
(
    SELECT
        c.security_id,
        c.trade_date,
        c.pivot_date,
        c.pivot_price,
        c.pivot_proximity_pct,

        cal.previous_trading_date,

        prev.pivot_proximity_pct
            AS previous_pivot_proximity_pct

    FROM current_rows c

    LEFT JOIN ref.trading_calendar cal
      ON cal.traded_date = c.trade_date

    LEFT JOIN trn.stock_setup_readiness_daily prev
      ON prev.security_id = c.security_id
     AND prev.trade_date = cal.previous_trading_date
     AND prev.pivot_date = c.pivot_date
     AND prev.pivot_price = c.pivot_price
     AND prev.pivot_proximity_pct IS NOT NULL
),

calculated AS
(
    SELECT
        security_id,
        trade_date,

        CASE
            WHEN pivot_date IS NULL
              OR pivot_price IS NULL
              OR pivot_proximity_pct IS NULL
              OR previous_pivot_proximity_pct IS NULL
            THEN NULL

            ELSE ROUND(
                (
                    pivot_proximity_pct
                    - previous_pivot_proximity_pct
                )::numeric,
                4
            )
        END AS pivot_proximity_change_1d_pct

    FROM previous_comparable
)

UPDATE trn.stock_setup_readiness_daily r

SET
    pivot_proximity_change_1d_pct =
        c.pivot_proximity_change_1d_pct,

    pivot_proximity_direction =
        CASE
            WHEN c.pivot_proximity_change_1d_pct IS NULL
                THEN NULL

            WHEN c.pivot_proximity_change_1d_pct > 0
                THEN 'APPROACHING_PIVOT'

            WHEN c.pivot_proximity_change_1d_pct < 0
                THEN 'RETREATING_FROM_PIVOT'

            ELSE 'UNCHANGED'
        END,

    created_date = CURRENT_TIMESTAMP

FROM calculated c

WHERE r.security_id = c.security_id
  AND r.trade_date = c.trade_date;