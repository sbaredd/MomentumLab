-- ============================================================================
-- MomentumLab
-- Feature : BQ07 - Energy Stored Score
-- File    : 043_bq07_energy_stored_score.sql
-- Version : 2.0
--
-- Production scope:
--   NIFTY_100
--   Selected trade date
--
-- Maximum Score: 10
-- ============================================================================

ALTER TABLE trn.stock_base_quality_daily
ADD COLUMN IF NOT EXISTS energy_stored_score INTEGER;


WITH params AS
(
    SELECT
        DATE '2026-08-13' AS evaluation_date
),

components AS
(
    SELECT
        q.security_id,
        q.trade_date,

        q.recent_5_price_tightness_pct,
        q.range_contraction_pct,
        q.volume_dryup_pct,

        -- Price Tightness: 0-4
        CASE
            WHEN q.recent_5_price_tightness_pct IS NULL THEN NULL
            WHEN q.recent_5_price_tightness_pct <= 5  THEN 4
            WHEN q.recent_5_price_tightness_pct <= 8  THEN 3
            WHEN q.recent_5_price_tightness_pct <= 12 THEN 2
            WHEN q.recent_5_price_tightness_pct <= 16 THEN 1
            ELSE 0
        END AS tightness_points,

        -- Range Contraction: 0-3
        CASE
            WHEN q.range_contraction_pct IS NULL THEN NULL
            WHEN q.range_contraction_pct >= 30 THEN 3
            WHEN q.range_contraction_pct >= 15 THEN 2
            WHEN q.range_contraction_pct > 0   THEN 1
            ELSE 0
        END AS contraction_points,

        -- Volume Dry-up: 0-3
        CASE
            WHEN q.volume_dryup_pct IS NULL THEN NULL
            WHEN q.volume_dryup_pct >= 40 THEN 3
            WHEN q.volume_dryup_pct >= 20 THEN 2
            WHEN q.volume_dryup_pct > 0   THEN 1
            ELSE 0
        END AS dryup_points

    FROM trn.stock_base_quality_daily q

    JOIN ref.security_universe_membership um
      ON um.security_id = q.security_id
     AND um.universe_code = 'NIFTY_100'

    CROSS JOIN params p

    WHERE q.trade_date = p.evaluation_date
),

raw_scores AS
(
    SELECT
        security_id,
        trade_date,

        range_contraction_pct,
        volume_dryup_pct,

        tightness_points
        + contraction_points
        + dryup_points AS raw_energy_score

    FROM components

    WHERE tightness_points IS NOT NULL
      AND contraction_points IS NOT NULL
      AND dryup_points IS NOT NULL
),

scored AS
(
    SELECT
        security_id,
        trade_date,

        CASE
            WHEN range_contraction_pct <= 0
              OR volume_dryup_pct <= 0
            THEN LEAST(raw_energy_score, 4)

            ELSE raw_energy_score
        END AS energy_stored_score

    FROM raw_scores
)

UPDATE trn.stock_base_quality_daily q

SET energy_stored_score =
    s.energy_stored_score

FROM scored s

CROSS JOIN params p

WHERE q.security_id = s.security_id
  AND q.trade_date  = s.trade_date
  AND q.trade_date  = p.evaluation_date;