-- ============================================================================
-- MomentumLab
-- Feature : BQ02 - Range Contraction Score
-- File    : 038_bq02_range_contraction_score.sql
-- Version : 2.0
--
-- Purpose:
--   Score whether price range is contracting as the base develops.
--
-- Production scope:
--   NIFTY_100
--   Selected trade date
--
-- Score:
--   <= 0%      -> 0
--   >0 - <10%  -> 2
--   10 - <20%  -> 4
--   20 - <30%  -> 6
--   30 - <40%  -> 8
--   >=40%      -> 10
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
            WHEN q.range_contraction_pct IS NULL THEN NULL
            WHEN q.range_contraction_pct <= 0 THEN 0
            WHEN q.range_contraction_pct < 10 THEN 2
            WHEN q.range_contraction_pct < 20 THEN 4
            WHEN q.range_contraction_pct < 30 THEN 6
            WHEN q.range_contraction_pct < 40 THEN 8
            ELSE 10
        END AS range_contraction_score

    FROM trn.stock_base_quality_daily q

    JOIN ref.security_universe_membership um
      ON um.security_id = q.security_id

    CROSS JOIN params p

    WHERE q.trade_date = p.trade_date
      AND um.universe_code = p.universe_code
      AND q.range_contraction_pct IS NOT NULL
)

UPDATE trn.stock_base_quality_daily q

SET range_contraction_score = s.range_contraction_score

FROM scored s

WHERE q.security_id = s.security_id
  AND q.trade_date  = s.trade_date;