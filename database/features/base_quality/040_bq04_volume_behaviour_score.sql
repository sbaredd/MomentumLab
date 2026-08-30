-- ============================================================================
-- MomentumLab
-- Feature : BQ04 - Volume Behaviour Score
-- File    : 040_bq04_volume_behaviour_score.sql
-- Version : 2.0
--
-- Purpose:
--   Score whether volume behaviour within the base indicates
--   accumulation rather than distribution.
--
-- Production scope:
--   NIFTY_100
--   Selected trade date
--
-- Input:
--   down_vs_up_volume_ratio
--
-- Interpretation:
--   Lower ratio = lighter volume on down days relative to up days
--               = healthier volume behaviour.
--
-- Score:
--   <= 0.40       -> 10
--   >0.40 - 0.50  -> 8
--   >0.50 - 0.60  -> 6
--   >0.60 - 0.75  -> 4
--   >0.75 - 1.00  -> 2
--   >1.00         -> 0
-- ============================================================================

WITH params AS
(
    SELECT
        DATE '2026-08-13' AS trade_date,
        'NIFTY_100'::varchar AS universe_code
),

scored AS
(
    SELECT
        q.security_id,
        q.trade_date,

        CASE
            WHEN q.down_vs_up_volume_ratio IS NULL THEN NULL
            WHEN q.down_vs_up_volume_ratio <= 0.40 THEN 10
            WHEN q.down_vs_up_volume_ratio <= 0.50 THEN 8
            WHEN q.down_vs_up_volume_ratio <= 0.60 THEN 6
            WHEN q.down_vs_up_volume_ratio <= 0.75 THEN 4
            WHEN q.down_vs_up_volume_ratio <= 1.00 THEN 2
            ELSE 0
        END AS volume_behaviour_score

    FROM trn.stock_base_quality_daily q

    JOIN ref.security_universe_membership um
      ON um.security_id = q.security_id

    CROSS JOIN params p

    WHERE q.trade_date = p.trade_date
      AND um.universe_code = p.universe_code
)

UPDATE trn.stock_base_quality_daily q

SET volume_behaviour_score =
    s.volume_behaviour_score

FROM scored s

WHERE q.security_id = s.security_id
  AND q.trade_date  = s.trade_date;