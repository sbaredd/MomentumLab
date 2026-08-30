-- ============================================================================
-- MomentumLab
-- Feature : BQ06 - Setup Maturity Score
-- File    : 042_bq06_setup_maturity_score.sql
-- Version : 2.0
--
-- Purpose:
--   Score whether the setup has had enough time after the base low
--   to mature into an actionable structure.
--
-- Primary Input:
--   post_low_sessions
--
-- Score:
--    0 - 2 sessions   -> 0
--    3 - 4 sessions   -> 2
--    5 - 7 sessions   -> 4
--    8 - 10 sessions  -> 6
--   11 - 14 sessions  -> 8
--   >= 15 sessions    -> 10
--
-- Scope:
--   NIFTY_100
--   Selected evaluation date
-- ============================================================================


ALTER TABLE trn.stock_base_quality_daily
ADD COLUMN IF NOT EXISTS setup_maturity_score INTEGER;


WITH params AS
(
    SELECT DATE '2026-08-13' AS evaluation_date
),

scored AS
(
    SELECT
        q.security_id,
        q.trade_date,

        CASE
            WHEN q.post_low_sessions IS NULL THEN NULL
            WHEN q.post_low_sessions <= 2  THEN 0
            WHEN q.post_low_sessions <= 4  THEN 2
            WHEN q.post_low_sessions <= 7  THEN 4
            WHEN q.post_low_sessions <= 10 THEN 6
            WHEN q.post_low_sessions <= 14 THEN 8
            ELSE 10
        END AS setup_maturity_score

    FROM trn.stock_base_quality_daily q

    JOIN ref.security_universe_membership um
      ON um.security_id = q.security_id
     AND um.universe_code = 'NIFTY_100'

    CROSS JOIN params p

    WHERE q.trade_date = p.evaluation_date
)

UPDATE trn.stock_base_quality_daily q

SET setup_maturity_score = s.setup_maturity_score

FROM scored s

CROSS JOIN params p

WHERE q.security_id = s.security_id
  AND q.trade_date  = s.trade_date
  AND q.trade_date  = p.evaluation_date;