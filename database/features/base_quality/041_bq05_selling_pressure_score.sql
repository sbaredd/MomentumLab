-- ============================================================================
-- MomentumLab
-- Feature : BQ05 - Selling Pressure Score
-- File    : 041_bq05_selling_pressure_score.sql
-- Version : 2.0
-- ============================================================================

ALTER TABLE trn.stock_base_quality_daily
ADD COLUMN IF NOT EXISTS selling_pressure_score INTEGER;


WITH params AS
(
    SELECT DATE '2026-08-13' AS evaluation_date
),

component_scores AS
(
    SELECT
        q.security_id,
        q.trade_date,

        -- Frequency of down days
        CASE
            WHEN q.down_day_ratio_pct IS NULL THEN NULL
            WHEN q.down_day_ratio_pct <= 30 THEN 8
            WHEN q.down_day_ratio_pct <= 40 THEN 4
            WHEN q.down_day_ratio_pct <= 50 THEN 2
            ELSE 0
        END AS frequency_score,

        -- Severity of down days
        CASE
            WHEN q.avg_down_day_return_pct IS NULL THEN NULL
            WHEN q.avg_down_day_return_pct >= -1.0 THEN 10
            WHEN q.avg_down_day_return_pct >= -1.5 THEN 8
            WHEN q.avg_down_day_return_pct >= -2.0 THEN 6
            WHEN q.avg_down_day_return_pct >= -2.5 THEN 4
            ELSE 2
        END AS severity_score,

        -- High-volume selling
        CASE
            WHEN q.high_volume_down_day_ratio_pct IS NULL THEN NULL
            WHEN q.high_volume_down_day_ratio_pct = 0 THEN 10
            WHEN q.high_volume_down_day_ratio_pct <= 20 THEN 8
            WHEN q.high_volume_down_day_ratio_pct <= 40 THEN 6
            WHEN q.high_volume_down_day_ratio_pct <= 60 THEN 4
            WHEN q.high_volume_down_day_ratio_pct <= 80 THEN 2
            ELSE 0
        END AS high_volume_score

    FROM trn.stock_base_quality_daily q

    JOIN ref.security_universe_membership um
      ON um.security_id = q.security_id
     AND um.universe_code = 'NIFTY_100'

    CROSS JOIN params p

    WHERE q.trade_date = p.evaluation_date
),

weighted AS
(
    SELECT
        security_id,
        trade_date,

        (
            0.30 * frequency_score
          + 0.30 * severity_score
          + 0.40 * high_volume_score
        ) AS raw_score

    FROM component_scores

    WHERE frequency_score IS NOT NULL
      AND severity_score IS NOT NULL
      AND high_volume_score IS NOT NULL
),

scored AS
(
    SELECT
        security_id,
        trade_date,

        CASE
            WHEN raw_score >= 9 THEN 10
            WHEN raw_score >= 7 THEN 8
            WHEN raw_score >= 5 THEN 6
            WHEN raw_score >= 3 THEN 4
            WHEN raw_score >= 1 THEN 2
            ELSE 0
        END AS selling_pressure_score

    FROM weighted
)

UPDATE trn.stock_base_quality_daily q

SET selling_pressure_score = s.selling_pressure_score

FROM scored s

CROSS JOIN params p

WHERE q.security_id = s.security_id
  AND q.trade_date  = s.trade_date
  AND q.trade_date  = p.evaluation_date;