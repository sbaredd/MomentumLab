-- ============================================================================
-- MomentumLab
-- Feature : BQ03 - Price Structure Score
-- File    : 039_bq03_price_structure_score.sql
-- Version : 2.0
--
-- Purpose:
--   Score the structural quality of post-low price action.
--
-- Structure Strength:
--
--   40% Higher-High Ratio
-- + 40% Higher-Low Ratio
-- + 20% inverse Lower-Low Ratio
--
-- Production scope:
--   NIFTY_100
--   Selected trade date
--
-- Score:
--   < 50%       -> 0
--   50 - <60%   -> 2
--   60 - <70%   -> 4
--   70 - <80%   -> 6
--   80 - <90%   -> 8
--   >=90%       -> 10
-- ============================================================================

WITH params AS
(
    SELECT
        DATE '2026-08-13' AS trade_date,
        'NIFTY_100'::varchar AS universe_code
),

structure AS
(
    SELECT
        q.security_id,
        q.trade_date,

        (
            0.40 * q.higher_high_ratio_pct
          + 0.40 * q.higher_low_ratio_pct
          + 0.20 * (100 - q.lower_low_ratio_pct)
        ) AS structure_strength_pct

    FROM trn.stock_base_quality_daily q

    JOIN ref.security_universe_membership um
      ON um.security_id = q.security_id

    CROSS JOIN params p

    WHERE q.trade_date = p.trade_date
      AND um.universe_code = p.universe_code
),

scored AS
(
    SELECT
        security_id,
        trade_date,
        structure_strength_pct,

        CASE
            WHEN structure_strength_pct IS NULL THEN NULL
            WHEN structure_strength_pct < 50 THEN 0
            WHEN structure_strength_pct < 60 THEN 2
            WHEN structure_strength_pct < 70 THEN 4
            WHEN structure_strength_pct < 80 THEN 6
            WHEN structure_strength_pct < 90 THEN 8
            ELSE 10
        END AS price_structure_score

    FROM structure
)

UPDATE trn.stock_base_quality_daily q

SET price_structure_score = s.price_structure_score

FROM scored s

WHERE q.security_id = s.security_id
  AND q.trade_date  = s.trade_date;