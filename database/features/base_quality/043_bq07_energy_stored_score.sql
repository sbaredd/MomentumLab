-- ============================================================================
-- MomentumLab
-- Feature : BQ07 - Energy Stored Score
-- File    : 043_bq07_energy_stored_score.sql
--
-- Purpose:
--   Measure whether the right side of the base shows simultaneous:
--     1. Price tightness
--     2. Range contraction
--     3. Volume dry-up
--
-- Inputs:
--   recent_5_price_tightness_pct
--   range_contraction_pct
--   volume_dryup_pct
--
-- Component Points:
--
-- Price Tightness (0-4)
--   <= 5%   -> 4
--   <= 8%   -> 3
--   <= 12%  -> 2
--   <= 16%  -> 1
--   > 16%   -> 0
--
-- Range Contraction (0-3)
--   >= 30%  -> 3
--   >= 15%  -> 2
--   > 0%    -> 1
--   <= 0%   -> 0
--
-- Volume Dry-up (0-3)
--   >= 40%  -> 3
--   >= 20%  -> 2
--   > 0%    -> 1
--   <= 0%   -> 0
--
-- Confluence / Gating:
--   Energy Stored requires BOTH:
--      range_contraction_pct > 0
--      volume_dryup_pct > 0
--
--   If either condition is absent, score is capped at 4.
--
-- Maximum Score: 10
-- ============================================================================


ALTER TABLE trn.stock_base_quality_daily
ADD COLUMN IF NOT EXISTS energy_stored_score INTEGER;


WITH components AS
(
    SELECT
        security_id,
        trade_date,

        recent_5_price_tightness_pct,
        range_contraction_pct,
        volume_dryup_pct,

        -- ------------------------------------------------------------
        -- 1. Price Tightness: 0-4
        -- Lower is better
        -- ------------------------------------------------------------
        CASE
            WHEN recent_5_price_tightness_pct IS NULL THEN NULL
            WHEN recent_5_price_tightness_pct <= 5  THEN 4
            WHEN recent_5_price_tightness_pct <= 8  THEN 3
            WHEN recent_5_price_tightness_pct <= 12 THEN 2
            WHEN recent_5_price_tightness_pct <= 16 THEN 1
            ELSE 0
        END AS tightness_points,

        -- ------------------------------------------------------------
        -- 2. Range Contraction: 0-3
        -- Higher positive contraction is better
        -- ------------------------------------------------------------
        CASE
            WHEN range_contraction_pct IS NULL THEN NULL
            WHEN range_contraction_pct >= 30 THEN 3
            WHEN range_contraction_pct >= 15 THEN 2
            WHEN range_contraction_pct > 0   THEN 1
            ELSE 0
        END AS contraction_points,

        -- ------------------------------------------------------------
        -- 3. Volume Dry-up: 0-3
        -- Higher positive dry-up is better
        -- ------------------------------------------------------------
        CASE
            WHEN volume_dryup_pct IS NULL THEN NULL
            WHEN volume_dryup_pct >= 40 THEN 3
            WHEN volume_dryup_pct >= 20 THEN 2
            WHEN volume_dryup_pct > 0   THEN 1
            ELSE 0
        END AS dryup_points

    FROM trn.stock_base_quality_daily
),

raw_scores AS
(
    SELECT
        security_id,
        trade_date,

        recent_5_price_tightness_pct,
        range_contraction_pct,
        volume_dryup_pct,

        tightness_points,
        contraction_points,
        dryup_points,

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

            -- --------------------------------------------------------
            -- Confluence gate
            --
            -- A setup cannot receive a high Energy Stored score when
            -- either range contraction or volume dry-up is absent.
            -- --------------------------------------------------------
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

WHERE q.security_id = s.security_id
  AND q.trade_date  = s.trade_date;