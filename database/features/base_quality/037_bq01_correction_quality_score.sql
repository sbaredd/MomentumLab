-- ============================================================================
-- MomentumLab
-- Feature : BQ01 - Correction Quality Score
-- File    : 037_bq01_correction_quality_score.sql
--
-- Uses existing raw feature:
--   correction_depth_pct
--
-- Score:
--      0% -  3%  ->  6
--     >3% -  5%  ->  8
--     >5% - 10%  -> 10
--    >10% - 15%  ->  8
--    >15% - 20%  ->  6
--    >20% - 25%  ->  4
--    >25% - 30%  ->  2
--    >30%        ->  0
-- ============================================================================

WITH scored AS
(
    SELECT
        security_id,
        trade_date,
        correction_depth_pct,

        CASE
            WHEN correction_depth_pct IS NULL THEN NULL
            WHEN correction_depth_pct <= 3  THEN 6
            WHEN correction_depth_pct <= 5  THEN 8
            WHEN correction_depth_pct <= 10 THEN 10
            WHEN correction_depth_pct <= 15 THEN 8
            WHEN correction_depth_pct <= 20 THEN 6
            WHEN correction_depth_pct <= 25 THEN 4
            WHEN correction_depth_pct <= 30 THEN 2
            ELSE 0
        END AS correction_quality_score

    FROM trn.stock_base_quality_daily
)

UPDATE trn.stock_base_quality_daily q

SET
    correction_quality_score =
        s.correction_quality_score

FROM scored s

WHERE q.security_id = s.security_id
  AND q.trade_date  = s.trade_date;